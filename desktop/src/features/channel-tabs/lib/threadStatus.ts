import type { RelayEvent } from "@/shared/api/types";
import { KIND_THREAD_STATUS } from "@/shared/constants/kinds";

export const TASK_STATUSES = [
  "open",
  "in_progress",
  "awaiting_owner",
  "blocked",
  "done",
] as const;
export type TaskStatus = (typeof TASK_STATUSES)[number];
export const APPROVE_EMOJI = "✅";
export const DENY_EMOJI = "❌";
const HEX64 = /^[0-9a-f]{64}$/;
const DONE_LIMIT = 20;

export type ThreadTask = {
  rootId: string;
  channelId: string;
  status: TaskStatus;
  title: string;
  ask: { text: string; eventId: string } | null;
  author: string;
  createdAt: number;
  eventId: string;
};

export type TaskGroups = {
  needsYou: ThreadTask[];
  inProgress: ThreadTask[];
  blocked: ThreadTask[];
  done: ThreadTask[];
};

function rows(event: RelayEvent, name: string) {
  return event.tags.filter((tag) => tag[0] === name);
}

function single(event: RelayEvent, name: string) {
  const found = rows(event, name);
  return found.length === 1 ? found[0] : null;
}

export function parseThreadStatusEvent(event: RelayEvent): ThreadTask | null {
  if (event.kind !== KIND_THREAD_STATUS || event.content !== "") return null;
  const d = single(event, "d")?.[1];
  const channelId = single(event, "h")?.[1];
  const e = single(event, "e");
  const status = single(event, "status")?.[1];
  const title = single(event, "title")?.[1];
  if (!d || !channelId || !e || !status || title === undefined) return null;
  if (!HEX64.test(d) || e[1] !== d || (e[3] ?? "") !== "") return null;
  if (!(TASK_STATUSES as readonly string[]).includes(status)) return null;
  if (title.trim() === "" || [...title].length > 80) return null;
  const askRows = rows(event, "ask");
  if (askRows.length > 1) return null;
  const askRow = askRows[0];
  const ask =
    askRow && (askRow[1] ?? "").trim() !== "" && HEX64.test(askRow[2] ?? "")
      ? { text: askRow[1], eventId: askRow[2] }
      : null;
  if ((status === "awaiting_owner") !== Boolean(askRow) || (askRow && !ask))
    return null;
  return {
    rootId: d,
    channelId,
    status: status as TaskStatus,
    title,
    ask,
    author: event.pubkey,
    createdAt: event.created_at,
    eventId: event.id,
  };
}

function isNewer(candidate: ThreadTask, current: ThreadTask) {
  return candidate.createdAt !== current.createdAt
    ? candidate.createdAt > current.createdAt
    : candidate.eventId < current.eventId;
}

export function reduceThreadTasks(
  events: readonly RelayEvent[],
  channelId: string,
): Map<string, ThreadTask> {
  const tasks = new Map<string, ThreadTask>();
  for (const event of events) {
    const task = parseThreadStatusEvent(event);
    if (!task || task.channelId !== channelId) continue;
    const current = tasks.get(task.rootId);
    if (!current || isNewer(task, current)) tasks.set(task.rootId, task);
  }
  return tasks;
}

export function groupThreadTasks(tasks: Iterable<ThreadTask>): TaskGroups {
  const groups: TaskGroups = {
    needsYou: [],
    inProgress: [],
    blocked: [],
    done: [],
  };
  for (const task of tasks) {
    if (task.status === "awaiting_owner") groups.needsYou.push(task);
    else if (task.status === "blocked") groups.blocked.push(task);
    else if (task.status === "done") groups.done.push(task);
    else groups.inProgress.push(task);
  }
  const newestFirst = (a: ThreadTask, b: ThreadTask) =>
    b.createdAt - a.createdAt || (a.eventId < b.eventId ? -1 : 1);
  for (const list of Object.values(groups)) list.sort(newestFirst);
  groups.done = groups.done.slice(0, DONE_LIMIT);
  return groups;
}

export function buildThreadStatusTags(input: {
  rootId: string;
  channelId: string;
  status: TaskStatus;
  title: string;
  ask?: { text: string; eventId: string } | null;
}): string[][] {
  const tags = [
    ["d", input.rootId],
    ["h", input.channelId],
    ["e", input.rootId],
    ["status", input.status],
    ["title", [...input.title].slice(0, 80).join("")],
  ];
  if (input.status === "awaiting_owner" && input.ask)
    tags.push(["ask", input.ask.text, input.ask.eventId]);
  return tags;
}

export function isApprovalRequest(
  tags: readonly string[][] | undefined,
): boolean {
  return (tags ?? []).some(
    (tag) => tag[0] === "notification" && tag[1] === "approval",
  );
}

export function approvalDecision(
  reactions: readonly { emoji: string; reactedByCurrentUser?: boolean }[],
): "approve" | "deny" | null {
  if (
    reactions.some((r) => r.emoji === APPROVE_EMOJI && r.reactedByCurrentUser)
  )
    return "approve";
  if (reactions.some((r) => r.emoji === DENY_EMOJI && r.reactedByCurrentUser))
    return "deny";
  return null;
}
