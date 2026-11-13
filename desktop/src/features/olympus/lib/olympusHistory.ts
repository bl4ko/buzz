import type { RelayEvent } from "@/shared/api/types";
import { KIND_OLYMPUS_CHANGE_RESULT } from "@/shared/constants/kinds";

export type OlympusHistoryEntry = {
  id: string;
  author: string;
  createdAt: number;
  status: "accepted" | "refused";
  action: string;
  workspace: string | null;
  agent: string | null;
  schedule: string | null;
  proposal: string | null;
  reason: string | null;
  request: string | null;
};

const HISTORY_LIMIT = 500;

function tag(event: RelayEvent, name: string): string | null {
  const values = event.tags.filter((item) => item[0] === name);
  return values.length === 1 && typeof values[0]?.[1] === "string"
    ? (values[0][1] as string)
    : null;
}

export function parseOlympusHistoryEntry(
  event: RelayEvent,
  operators: ReadonlySet<string>,
): OlympusHistoryEntry | null {
  if (
    event.kind !== KIND_OLYMPUS_CHANGE_RESULT ||
    !operators.has(event.pubkey)
  ) {
    return null;
  }
  const status = tag(event, "status");
  const action = tag(event, "action");
  if ((status !== "accepted" && status !== "refused") || !action) return null;
  let reason: string | null = null;
  try {
    const content: unknown = JSON.parse(event.content);
    if (
      typeof content === "object" &&
      content !== null &&
      "reason" in content &&
      typeof content.reason === "string" &&
      content.reason
    ) {
      reason = content.reason;
    }
  } catch {}
  return {
    id: event.id,
    author: event.pubkey,
    createdAt: event.created_at,
    status,
    action,
    workspace: tag(event, "workspace"),
    agent: tag(event, "agent"),
    schedule: tag(event, "schedule"),
    proposal: tag(event, "proposal"),
    reason,
    request: tag(event, "e"),
  };
}

export function mergeOlympusHistory(
  current: readonly RelayEvent[],
  incoming: readonly RelayEvent[],
): RelayEvent[] {
  const byId = new Map<string, RelayEvent>();
  for (const event of [...current, ...incoming]) {
    if (event.kind === KIND_OLYMPUS_CHANGE_RESULT) byId.set(event.id, event);
  }
  return [...byId.values()]
    .sort((a, b) => b.created_at - a.created_at || a.id.localeCompare(b.id))
    .slice(0, HISTORY_LIMIT);
}

export function listOlympusHistory(
  events: readonly RelayEvent[],
  operators: ReadonlySet<string>,
  scope: { workspace?: string; agent?: string | null } = {},
): OlympusHistoryEntry[] {
  return events.flatMap((event) => {
    const entry = parseOlympusHistoryEntry(event, operators);
    if (!entry) return [];
    if (scope.workspace !== undefined && entry.workspace !== scope.workspace) {
      return [];
    }
    if (scope.agent !== undefined && entry.agent !== scope.agent) return [];
    return [entry];
  });
}
