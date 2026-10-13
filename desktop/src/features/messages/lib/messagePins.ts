import type { TimelineMessage } from "@/features/messages/types";
import type { RelayEvent } from "@/shared/api/types";
import {
  KIND_STREAM_MESSAGE,
  KIND_STREAM_MESSAGE_PINNED,
  KIND_STREAM_MESSAGE_V2,
} from "@/shared/constants/kinds";

const PINNABLE_MESSAGE_KINDS: ReadonlySet<number> = new Set([
  KIND_STREAM_MESSAGE,
  KIND_STREAM_MESSAGE_V2,
]);

export type PinStatus = "pinned" | "unpinned";

export type PinRecord = {
  eventId: string;
  pubkey: string;
  createdAt: number;
  channelId: string;
  targetId: string;
  status: PinStatus;
};

export type PinnedMessage = {
  pin: PinRecord;
  target: RelayEvent;
};

function singleTagValue(tags: string[][], name: string): string | null {
  const matches = tags.filter((tag) => tag[0] === name);
  if (matches.length !== 1) return null;
  const value = matches[0][1];
  return typeof value === "string" && value.length > 0 ? value : null;
}

export function isPinnableMessage(
  message: Pick<TimelineMessage, "kind" | "pending">,
): boolean {
  return (
    !message.pending &&
    message.kind !== undefined &&
    PINNABLE_MESSAGE_KINDS.has(message.kind)
  );
}

export function parsePinEvent(event: RelayEvent): PinRecord | null {
  if (event.kind !== KIND_STREAM_MESSAGE_PINNED) return null;
  const channelId = singleTagValue(event.tags, "h");
  const targetId = singleTagValue(event.tags, "e");
  const status = singleTagValue(event.tags, "status");
  if (!channelId || !targetId) return null;
  if (status !== "pinned" && status !== "unpinned") return null;
  return {
    eventId: event.id,
    pubkey: event.pubkey,
    createdAt: event.created_at,
    channelId,
    targetId,
    status,
  };
}

export function isNewerPin(candidate: PinRecord, current: PinRecord): boolean {
  if (candidate.createdAt !== current.createdAt) {
    return candidate.createdAt > current.createdAt;
  }
  return candidate.eventId < current.eventId;
}

export function reducePinEvents(
  events: readonly RelayEvent[],
  channelId: string,
): Map<string, PinRecord> {
  const latest = new Map<string, PinRecord>();
  for (const event of events) {
    const record = parsePinEvent(event);
    if (!record || record.channelId !== channelId) continue;
    const current = latest.get(record.targetId);
    if (!current || isNewerPin(record, current)) {
      latest.set(record.targetId, record);
    }
  }
  return latest;
}

export function selectPinnedRecords(
  state: ReadonlyMap<string, PinRecord>,
): PinRecord[] {
  return [...state.values()]
    .filter((record) => record.status === "pinned")
    .sort((a, b) => (isNewerPin(a, b) ? -1 : isNewerPin(b, a) ? 1 : 0));
}

export function selectPinnedMessages(
  records: readonly PinRecord[],
  targetsById: ReadonlyMap<string, RelayEvent>,
  deletedTargetIds: ReadonlySet<string>,
): PinnedMessage[] {
  const pinned: PinnedMessage[] = [];
  for (const pin of records) {
    if (deletedTargetIds.has(pin.targetId)) continue;
    const target = targetsById.get(pin.targetId);
    if (!target) continue;
    pinned.push({ pin, target });
  }
  return pinned;
}

export function mergePinEvent(
  current: readonly RelayEvent[],
  event: RelayEvent,
): RelayEvent[] {
  if (current.some((existing) => existing.id === event.id)) {
    return current as RelayEvent[];
  }
  return [...current, event];
}

export function buildPinEventTags(
  channelId: string,
  targetId: string,
  pinned: boolean,
): string[][] {
  return [
    ["h", channelId],
    ["e", targetId],
    ["status", pinned ? "pinned" : "unpinned"],
  ];
}

export function nextPinCreatedAt(
  nowSeconds: number,
  current: PinRecord | undefined,
): number {
  return current ? Math.max(nowSeconds, current.createdAt + 1) : nowSeconds;
}

export function deletionTargetIds(event: RelayEvent): string[] {
  return event.tags
    .filter((tag) => tag[0] === "e" && typeof tag[1] === "string")
    .map((tag) => tag[1]);
}
