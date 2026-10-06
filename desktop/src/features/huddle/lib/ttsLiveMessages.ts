import { getThreadReference } from "@/features/messages/lib/threading";
import {
  KIND_STREAM_MESSAGE,
  KIND_STREAM_MESSAGE_EDIT,
  KIND_STREAM_MESSAGE_V2,
} from "../../../shared/constants/kinds.ts";

export type LiveTtsEvent = {
  id: string;
  kind: number;
  pubkey: string;
  content: string;
  tags: string[][];
};

export type LiveTtsEligibility =
  | { text: string; reason: null }
  | {
      text: null;
      reason:
        | "unsupported_kind"
        | "h_tag_mismatch"
        | "author_not_agent"
        | "self_authored"
        | "not_final"
        | "outside_thread"
        | "empty_or_system";
    };

export type LiveTtsRouteResult =
  | "queued"
  | "disabled"
  | "already_spoken"
  | Exclude<LiveTtsEligibility, { text: string }>["reason"];

export type LiveTtsThread = {
  rootId: string;
  messageIds: Set<string>;
  spokenMessageIds: Set<string>;
};

const MAX_TRACKED_THREAD_IDS = 5000;

export function createLiveTtsThread(rootId: string): LiveTtsThread {
  return { rootId, messageIds: new Set(), spokenMessageIds: new Set() };
}

function rememberBounded(ids: Set<string>, id: string) {
  ids.delete(id);
  ids.add(id);
  if (ids.size > MAX_TRACKED_THREAD_IDS) {
    const oldest = ids.values().next().value;
    if (oldest !== undefined) ids.delete(oldest);
  }
}

function editTargetId(event: LiveTtsEvent): string | null {
  return event.tags.find((tag) => tag[0] === "e")?.[1] ?? null;
}

/** Track thread membership on arrival so later final edits can be matched. */
export function observeLiveTtsThreadEvent(
  thread: LiveTtsThread,
  event: LiveTtsEvent,
) {
  if (
    event.kind === KIND_STREAM_MESSAGE &&
    getThreadReference(event.tags).rootId === thread.rootId
  ) {
    rememberBounded(thread.messageIds, event.id);
  }
}

function textWithoutAttachments(event: LiveTtsEvent): string {
  const urls = new Set(
    event.tags
      .filter((tag) => tag[0] === "imeta")
      .flatMap((tag) =>
        tag
          .slice(1)
          .filter((field) => field.startsWith("url "))
          .map((field) => field.slice(4)),
      ),
  );
  if (urls.size === 0) return event.content;
  const withoutMedia = event.content
    .split("\n")
    .filter(
      (line) => !Array.from(urls).some((url) => line.includes(`](${url})`)),
    )
    .join("\n");
  return withoutMedia.replace(
    /(^|\n)\s*\|\|\s*\n(?:\s*\n)*\s*\|\|\s*(?=\n|$)/gu,
    "$1",
  );
}

export function classifySpeakableAgentText(
  event: LiveTtsEvent,
  agentPubkeys: ReadonlySet<string>,
  selfPubkey: string | null,
  channelId: string,
  thread: LiveTtsThread | null = null,
): LiveTtsEligibility {
  const speakableKinds = thread
    ? [KIND_STREAM_MESSAGE, KIND_STREAM_MESSAGE_EDIT]
    : [KIND_STREAM_MESSAGE, KIND_STREAM_MESSAGE_V2];
  if (!speakableKinds.includes(event.kind))
    return { text: null, reason: "unsupported_kind" };
  if (!event.tags.some((tag) => tag[0] === "h" && tag[1] === channelId))
    return { text: null, reason: "h_tag_mismatch" };
  if (!agentPubkeys.has(event.pubkey))
    return { text: null, reason: "author_not_agent" };
  if (event.pubkey === selfPubkey)
    return { text: null, reason: "self_authored" };
  if (thread) {
    if (!event.tags.some((tag) => tag[0] === "voice" && tag[1] === "final"))
      return { text: null, reason: "not_final" };
    const inThread =
      event.kind === KIND_STREAM_MESSAGE_EDIT
        ? thread.messageIds.has(editTargetId(event) ?? "")
        : getThreadReference(event.tags).rootId === thread.rootId;
    if (!inThread) return { text: null, reason: "outside_thread" };
  }
  const content = textWithoutAttachments(event).trim();
  if (content.length === 0 || content.startsWith("[System]"))
    return { text: null, reason: "empty_or_system" };
  return { text: content, reason: null };
}

/** Classify and enqueue one live event through the production routing seam. */
export function routeLiveAgentText(
  event: LiveTtsEvent,
  agentPubkeys: ReadonlySet<string>,
  selfPubkey: string | null,
  channelId: string,
  routeId: number,
  enqueue: (text: string, routeId: number) => "queued" | "disabled",
  thread: LiveTtsThread | null = null,
): LiveTtsRouteResult {
  const eligibility = classifySpeakableAgentText(
    event,
    agentPubkeys,
    selfPubkey,
    channelId,
    thread,
  );
  if (eligibility.text === null) return eligibility.reason;
  if (!thread) return enqueue(eligibility.text, routeId);
  const messageId =
    event.kind === KIND_STREAM_MESSAGE_EDIT
      ? (editTargetId(event) ?? event.id)
      : event.id;
  if (thread.spokenMessageIds.has(messageId)) return "already_spoken";
  const result = enqueue(eligibility.text, routeId);
  if (result === "queued") rememberBounded(thread.spokenMessageIds, messageId);
  return result;
}

/**
 * Serialize native speak calls so live messages enter the bounded Pocket queue
 * in thread arrival order even when the bridge resolves calls asynchronously.
 */
export function createOrderedSpeaker(
  speak: (
    text: string,
    routeId: number,
    speakerPubkey: string,
  ) => Promise<void>,
  onError: (error: unknown) => void,
  initiallyEnabled = true,
  onDrop: (routeId: number, reason: "disabled") => void = () => {},
): {
  enqueue: (
    text: string,
    routeId: number | undefined,
    speakerPubkey: string,
  ) => "queued" | "disabled";
  setEnabled: (enabled: boolean) => void;
} {
  let tail = Promise.resolve();
  let enabled = initiallyEnabled;
  let generation = 0;
  return {
    enqueue(text, routeId = 0, speakerPubkey) {
      if (!enabled) return "disabled";
      const queuedGeneration = generation;
      tail = tail
        .then(() => {
          if (!enabled || generation !== queuedGeneration) {
            onDrop(routeId, "disabled");
            return;
          }
          return speak(text, routeId, speakerPubkey);
        })
        .catch(onError);
      return "queued";
    },
    setEnabled(nextEnabled) {
      if (!nextEnabled) generation += 1;
      enabled = nextEnabled;
    },
  };
}

/** Ensure a delayed bootstrap snapshot cannot overwrite a newer live event. */
export function createLatestStateGate<T>(apply: (value: T) => void): {
  applyEvent: (value: T) => void;
  beginSnapshot: () => (value: T) => void;
} {
  let revision = 0;
  return {
    applyEvent(value) {
      revision += 1;
      apply(value);
    },
    beginSnapshot() {
      const snapshotRevision = revision;
      return (value) => {
        if (revision === snapshotRevision) apply(value);
      };
    },
  };
}

/** Hold live events until initial membership and TTS state are both known. */
export function createInitialTtsReadinessGate<T>(
  deliver: (event: T) => void,
  drop: (
    event: T,
    reason: "membership_unavailable" | "tts_state_unavailable",
  ) => void = () => {},
): {
  push: (event: T) => void;
  markMembershipKnown: () => void;
  markTtsStateKnown: () => void;
  fail: (reason: "membership_unavailable" | "tts_state_unavailable") => void;
} {
  let settled = false;
  let membershipKnown = false;
  let ttsStateKnown = false;
  let pending: T[] = [];
  const releaseIfReady = () => {
    if (settled || !membershipKnown || !ttsStateKnown) return;
    settled = true;
    const buffered = pending;
    pending = [];
    for (const event of buffered) deliver(event);
  };
  return {
    push(event) {
      if (settled) deliver(event);
      else pending.push(event);
    },
    markMembershipKnown() {
      membershipKnown = true;
      releaseIfReady();
    },
    markTtsStateKnown() {
      ttsStateKnown = true;
      releaseIfReady();
    },
    fail(reason) {
      if (settled) return;
      settled = true;
      const dropped = pending;
      pending = [];
      for (const event of dropped) drop(event, reason);
    },
  };
}
