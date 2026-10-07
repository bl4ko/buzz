import { relayClient } from "@/shared/api/relayClient";
import { PublishCanceledError } from "@/shared/api/relayEventPublisher";
import { getIdentity } from "@/shared/api/tauriIdentity";
import { matchesDetachedToastScope } from "@/features/messages/lib/detachedToastScope";
import {
  getRelayWsUrl,
  nip44DecryptFromSelf,
  nip44EncryptToSelf,
  signRelayEvent,
} from "@/shared/api/tauri";
import type { RelayEvent } from "@/shared/api/types";
import { KIND_EVENT_REMINDER } from "@/shared/constants/kinds";
import type {
  Reminder,
  ReminderContent,
  ReminderTarget,
} from "./reminderTypes";

const createdAtById = new Map<string, number>();
let writeGeneration = 0;

export function resetReminderWrites() {
  writeGeneration++;
  createdAtById.clear();
}

function nextCreatedAt(id: string, previousCreatedAt = 0): number {
  const createdAt = Math.max(
    Math.floor(Date.now() / 1_000),
    previousCreatedAt + 1,
    (createdAtById.get(id) ?? 0) + 1,
  );
  createdAtById.set(id, createdAt);
  return createdAt;
}

function extractDTag(event: RelayEvent): string | null {
  const tag = event.tags.find((t) => t[0] === "d");
  return tag?.[1] ?? null;
}

/**
 * Generate a reminder `d`-tag with 128 bits of entropy (NIP-ER line 58 MUST).
 * `crypto.randomUUID()` is UUIDv4 = only 122 random bits, so use 16 raw bytes.
 */
function randomDTag(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

function extractNotBefore(event: RelayEvent): number | undefined {
  const tag = event.tags.find((t) => t[0] === "not_before");
  return tag?.[1] ? parseNotBefore(tag[1]) : undefined;
}

/**
 * Parse a NIP-ER `not_before` tag value, mirroring the relay's strict
 * validator (NIP-ER line 60): ASCII digits only, no leading zero except "0",
 * and within `Number.MAX_SAFE_INTEGER`. Returns undefined for any value the
 * relay would reject, so the client ignores reminders the relay calls malformed.
 */
export function parseNotBefore(raw: string): number | undefined {
  if (!/^(0|[1-9][0-9]*)$/.test(raw)) return undefined;
  const val = Number(raw);
  return val <= Number.MAX_SAFE_INTEGER ? val : undefined;
}

/**
 * Validate decrypted reminder plaintext against the shape this client writes,
 * returning a typed content object or null. NIP-ER (Content section) requires
 * clients to ignore plaintext that is not a JSON object, has an unknown
 * `status`, or has a malformed target/note — so anything off-shape fails closed.
 */
export function parseReminderContent(
  plaintext: string,
): ReminderContent | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(plaintext);
  } catch {
    return null;
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    return null;
  }

  const obj = parsed as Record<string, unknown>;
  if (
    obj.status !== "pending" &&
    obj.status !== "done" &&
    obj.status !== "cancelled"
  ) {
    return null;
  }
  if (obj.note !== undefined && typeof obj.note !== "string") return null;

  let target: ReminderTarget | undefined;
  if (obj.target !== undefined) {
    const parsedTarget = parseTarget(obj.target);
    if (!parsedTarget) return null;
    target = parsedTarget;
  }

  // A reminder must reference a target or carry a non-empty note.
  if (!target && !(typeof obj.note === "string" && obj.note.length > 0)) {
    return null;
  }

  return { status: obj.status, target, note: obj.note as string | undefined };
}

function parseTarget(value: unknown): ReminderTarget | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }
  const t = value as Record<string, unknown>;
  if (
    typeof t.eventId !== "string" ||
    typeof t.channelId !== "string" ||
    typeof t.preview !== "string" ||
    typeof t.authorPubkey !== "string"
  ) {
    return null;
  }
  return {
    eventId: t.eventId,
    channelId: t.channelId,
    preview: t.preview,
    authorPubkey: t.authorPubkey,
  };
}

async function decryptReminder(event: RelayEvent): Promise<Reminder | null> {
  const dTag = extractDTag(event);
  if (!dTag) return null;

  let plaintext: string;
  try {
    plaintext = await nip44DecryptFromSelf(event.content);
  } catch {
    console.warn("[reminderService] failed to decrypt reminder:", event.id);
    return null;
  }

  const content = parseReminderContent(plaintext);
  if (!content) {
    console.warn("[reminderService] ignoring malformed reminder:", event.id);
    return null;
  }

  return {
    id: dTag,
    notBefore: extractNotBefore(event),
    content,
    createdAt: event.created_at,
    eventId: event.id,
  };
}

export async function fetchReminders(pubkey: string): Promise<Reminder[]> {
  const newestByDTag = new Map<string, RelayEvent>();
  let limit = 200;
  let until: number | undefined;
  for (;;) {
    const page = await relayClient.fetchEvents({
      kinds: [KIND_EVENT_REMINDER],
      authors: [pubkey],
      limit,
      ...(until === undefined ? {} : { until }),
    });
    for (const event of page) {
      const dTag = extractDTag(event);
      if (!dTag) continue;
      const existing = newestByDTag.get(dTag);
      if (
        !existing ||
        event.created_at > existing.created_at ||
        (event.created_at === existing.created_at && event.id < existing.id)
      ) {
        newestByDTag.set(dTag, event);
      }
    }
    if (page.length < limit) break;
    const oldest = Math.min(...page.map((event) => event.created_at));
    if (until === undefined || oldest < until) {
      until = oldest;
      continue;
    }
    if (limit < 1_000) {
      limit = 1_000;
      continue;
    }
    throw new Error(
      "Could not load saved items: a full relay page shares one timestamp.",
    );
  }
  const results = await Promise.all(
    [...newestByDTag.values()].map(decryptReminder),
  );
  return results.filter((r): r is Reminder => r !== null);
}

async function publishReminder(
  content: ReminderContent,
  tags: string[][],
  createdAt: number,
  action: string,
  expectedPubkey?: string,
): Promise<RelayEvent> {
  const generation = writeGeneration;
  const pubkey = (await getIdentity()).pubkey;
  if (
    generation !== writeGeneration ||
    (expectedPubkey !== undefined && expectedPubkey !== pubkey)
  ) {
    throw new PublishCanceledError();
  }
  const relayUrl = await getRelayWsUrl();
  const isCurrent = () =>
    generation === writeGeneration &&
    matchesDetachedToastScope(relayUrl, pubkey);
  const check = () => {
    if (!isCurrent()) throw new PublishCanceledError();
  };
  check();
  const ciphertext = await nip44EncryptToSelf(JSON.stringify(content));
  check();
  const event = await signRelayEvent({
    kind: KIND_EVENT_REMINDER,
    content: ciphertext,
    tags,
    createdAt,
  });
  check();
  if (event.pubkey !== pubkey) throw new PublishCanceledError();
  const published = await relayClient.publishEvent(
    event,
    `Timed out ${action} reminder.`,
    `Failed to ${action} reminder.`,
    isCurrent,
  );
  check();
  return published;
}

export async function createReminder(
  target: ReminderTarget,
  notBefore?: number,
  note?: string,
  previous?: Reminder,
  pubkey?: string,
): Promise<RelayEvent> {
  const dTag = previous?.id ?? randomDTag();
  const createdAt = nextCreatedAt(dTag, previous?.createdAt);
  const tags: string[][] = [["d", dTag]];
  if (notBefore !== undefined) tags.push(["not_before", String(notBefore)]);
  return publishReminder(
    { target, note, status: "pending" },
    tags,
    createdAt,
    "create",
    pubkey,
  );
}

export async function completeReminder(
  pubkey: string,
  reminder: Reminder,
): Promise<RelayEvent> {
  return publishReminder(
    { ...reminder.content, status: "done" },
    [["d", reminder.id]],
    nextCreatedAt(reminder.id, reminder.createdAt),
    "complete",
    pubkey,
  );
}

export async function snoozeReminder(
  pubkey: string,
  reminder: Reminder,
  newNotBefore?: number,
): Promise<RelayEvent> {
  const tags: string[][] = [["d", reminder.id]];
  if (newNotBefore !== undefined)
    tags.push(["not_before", String(newNotBefore)]);
  return publishReminder(
    { ...reminder.content, status: "pending" },
    tags,
    nextCreatedAt(reminder.id, reminder.createdAt),
    "snooze",
    pubkey,
  );
}

export async function cancelReminder(
  pubkey: string,
  reminder: Reminder,
): Promise<RelayEvent> {
  return publishReminder(
    { ...reminder.content, status: "cancelled" },
    [["d", reminder.id]],
    nextCreatedAt(reminder.id, reminder.createdAt),
    "cancel",
    pubkey,
  );
}
