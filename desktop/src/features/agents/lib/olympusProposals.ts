import type { RelayEvent } from "@/shared/api/types";
import { KIND_OLYMPUS_PROPOSAL } from "@/shared/constants/kinds";
import {
  mergeOlympusEvents,
  type OlympusWorkspaceGroup,
} from "./olympusAgents";

export const OLYMPUS_PROPOSAL_PHASES = [
  "pending",
  "applied",
  "rejected",
  "refused",
  "failed",
  "expired",
] as const;
export type OlympusProposalPhase = (typeof OLYMPUS_PROPOSAL_PHASES)[number];

const TARGET_KINDS = ["Agent", "Schedule", "Workspace"] as const;
const OPERATIONS = ["create", "patch", "delete"] as const;

export type OlympusProposalDiff = {
  path: string;
  from: string | null;
  to: string | null;
};

export type OlympusProposal = {
  author: string;
  eventId: string;
  name: string;
  workspace: string;
  requester: string;
  requesterKey: string | null;
  target: {
    kind: (typeof TARGET_KINDS)[number];
    namespace: string | null;
    name: string;
  };
  operation: (typeof OPERATIONS)[number];
  reason: string;
  diff: OlympusProposalDiff[];
  diffTruncated: boolean;
  highRisk: string[];
  createdAt: number;
  expiresAt: number;
  digest: string;
  phase: OlympusProposalPhase;
  result: {
    reason: string | null;
    request: string | null;
    at: number | null;
  } | null;
};

type Json = Record<string, unknown>;

const HEX = /^[0-9a-f]{64}$/;

function isObject(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function text(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function oneOf<T extends string>(
  values: readonly T[],
  value: unknown,
): T | null {
  return typeof value === "string" &&
    (values as readonly string[]).includes(value)
    ? (value as T)
    : null;
}

function singleTag(event: RelayEvent, name: string): string | null {
  const values = event.tags.filter((tag) => tag[0] === name);
  return values.length === 1 && typeof values[0][1] === "string"
    ? values[0][1]
    : null;
}

function nullableText(value: unknown): string | null | undefined {
  if (value === null) return null;
  return typeof value === "string" ? value : undefined;
}

function parseDiff(value: unknown): OlympusProposalDiff[] | null {
  if (!Array.isArray(value)) return null;
  const diff: OlympusProposalDiff[] = [];
  for (const entry of value) {
    if (!isObject(entry)) return null;
    const path = text(entry.path);
    const from = nullableText(entry.from);
    const to = nullableText(entry.to);
    if (!path || from === undefined || to === undefined) return null;
    diff.push({ path, from, to });
  }
  return diff;
}

export function parseOlympusProposal(
  event: RelayEvent,
  trustedAuthors: ReadonlySet<string>,
): OlympusProposal | null {
  if (
    event.kind !== KIND_OLYMPUS_PROPOSAL ||
    !trustedAuthors.has(event.pubkey) ||
    singleTag(event, "status") !== "active"
  ) {
    return null;
  }
  const d = singleTag(event, "d");
  let content: unknown;
  try {
    content = JSON.parse(event.content);
  } catch {
    return null;
  }
  if (!isObject(content) || content.v !== 1 || !isObject(content.target)) {
    return null;
  }
  const target = content.target;
  const name = text(content.name);
  const workspace = text(target.workspace);
  const targetKind = oneOf(TARGET_KINDS, target.kind);
  const targetName = text(target.name);
  const operation = oneOf(OPERATIONS, content.operation);
  const phase = oneOf(OLYMPUS_PROPOSAL_PHASES, content.phase);
  const digest = text(content.digest);
  const diff = parseDiff(content.diff);
  const workspaceTag = singleTag(event, "workspace");
  if (
    !name ||
    name !== d ||
    !workspace ||
    (workspaceTag !== null && workspaceTag !== workspace) ||
    !targetKind ||
    !targetName ||
    !operation ||
    !phase ||
    !digest ||
    !HEX.test(digest) ||
    !diff ||
    typeof content.reason !== "string" ||
    !Number.isFinite(content.createdAt) ||
    !Number.isFinite(content.expiresAt)
  ) {
    return null;
  }
  const highRisk = Array.isArray(content.highRisk)
    ? content.highRisk.filter(
        (item): item is string => typeof item === "string" && item.length > 0,
      )
    : [];
  const requesterKey =
    [text(content.requesterKey), singleTag(event, "requester")]
      .map((key) => key?.toLowerCase() ?? null)
      .find((key) => key !== null && HEX.test(key)) ?? null;
  const result = isObject(content.result)
    ? {
        reason: text(content.result.reason),
        request: text(content.result.request),
        at:
          typeof content.result.at === "number" &&
          Number.isFinite(content.result.at)
            ? content.result.at
            : null,
      }
    : null;
  return {
    author: event.pubkey,
    eventId: event.id,
    name,
    workspace,
    requester: text(content.requester) ?? "unknown agent",
    requesterKey,
    target: {
      kind: targetKind,
      namespace: text(target.namespace),
      name: targetName,
    },
    operation,
    reason: content.reason,
    diff,
    diffTruncated: content.diffTruncated === true,
    highRisk,
    createdAt: content.createdAt as number,
    expiresAt: content.expiresAt as number,
    digest,
    phase,
    result,
  };
}

export function olympusOperators(
  groups: readonly OlympusWorkspaceGroup[],
): Set<string> {
  return new Set(groups.map((group) => group.author));
}

export function listOlympusProposals(
  events: readonly RelayEvent[],
  trustedAuthors: ReadonlySet<string>,
): OlympusProposal[] {
  return mergeOlympusEvents([], events)
    .flatMap((event) => {
      const proposal = parseOlympusProposal(event, trustedAuthors);
      return proposal ? [proposal] : [];
    })
    .sort(
      (left, right) =>
        right.createdAt - left.createdAt || left.name.localeCompare(right.name),
    );
}

export function isOlympusProposalOpen(
  proposal: OlympusProposal,
  nowSeconds: number,
) {
  return proposal.phase === "pending" && proposal.expiresAt > nowSeconds;
}

export function olympusProposalKey(proposal: { author: string; name: string }) {
  return `proposal:${proposal.author}:${proposal.name}`;
}

export const OLYMPUS_PROPOSAL_FILTERS = [
  ...OLYMPUS_PROPOSAL_PHASES,
  "all",
] as const;
export type OlympusProposalFilter = (typeof OLYMPUS_PROPOSAL_FILTERS)[number];

export function olympusProposalStatus(
  proposal: Pick<OlympusProposal, "phase" | "expiresAt">,
  nowSeconds: number,
): OlympusProposalPhase {
  return proposal.phase === "pending" && proposal.expiresAt <= nowSeconds
    ? "expired"
    : proposal.phase;
}

export function countOlympusProposals(
  proposals: readonly OlympusProposal[],
  nowSeconds: number,
): Record<OlympusProposalFilter, number> {
  const counts = Object.fromEntries(
    OLYMPUS_PROPOSAL_FILTERS.map((filter) => [filter, 0]),
  ) as Record<OlympusProposalFilter, number>;
  for (const proposal of proposals) {
    counts[olympusProposalStatus(proposal, nowSeconds)] += 1;
    counts.all += 1;
  }
  return counts;
}

export function filterOlympusProposals(
  proposals: readonly OlympusProposal[],
  filter: OlympusProposalFilter,
  nowSeconds: number,
): OlympusProposal[] {
  return proposals
    .filter(
      (proposal) =>
        filter === "all" ||
        olympusProposalStatus(proposal, nowSeconds) === filter,
    )
    .sort(
      (left, right) =>
        right.createdAt - left.createdAt || left.name.localeCompare(right.name),
    );
}

export function countPendingOlympusProposals(
  proposals: readonly OlympusProposal[],
  nowSeconds: number,
  requesterKey?: string | null,
): number {
  return proposals.filter(
    (proposal) =>
      isOlympusProposalOpen(proposal, nowSeconds) &&
      (requesterKey === undefined || proposal.requesterKey === requesterKey),
  ).length;
}

export function nextOlympusProposalExpiry(
  proposals: readonly OlympusProposal[],
  nowSeconds: number,
): number | null {
  let next: number | null = null;
  for (const proposal of proposals) {
    if (isOlympusProposalOpen(proposal, nowSeconds)) {
      next =
        next === null ? proposal.expiresAt : Math.min(next, proposal.expiresAt);
    }
  }
  return next;
}

export const OLYMPUS_DIFF_INLINE_MAX = 80;
const LINE_DIFF_MAX_CELLS = 250_000;

export type OlympusDiffLine = { type: "same" | "del" | "add"; text: string };

export type OlympusDiffValue = {
  text: string;
  truncated: boolean;
};

export function decodeOlympusDiffValue(
  raw: string | null,
): OlympusDiffValue | null {
  if (raw === null) return null;
  const candidates = raw.startsWith('"')
    ? [raw, `${raw}"`, `${raw.replace(/\\+$/, "")}"`]
    : [raw];
  for (const [index, candidate] of candidates.entries()) {
    try {
      const parsed: unknown = JSON.parse(candidate);
      const text =
        typeof parsed === "string"
          ? parsed
          : candidate.length > OLYMPUS_DIFF_INLINE_MAX &&
              typeof parsed === "object" &&
              parsed !== null
            ? JSON.stringify(parsed, null, 2)
            : candidate;
      return { text, truncated: index > 0 };
    } catch {}
  }
  return { text: raw, truncated: false };
}

export function isOlympusLongDiff(
  from: OlympusDiffValue | null,
  to: OlympusDiffValue | null,
) {
  return [from, to].some(
    (value) =>
      value !== null &&
      (value.text.includes("\n") ||
        value.text.length > OLYMPUS_DIFF_INLINE_MAX),
  );
}

export function olympusLineDiff(
  from: string | null,
  to: string | null,
): OlympusDiffLine[] {
  const left = from === null ? [] : from.split("\n");
  const right = to === null ? [] : to.split("\n");
  let start = 0;
  while (
    start < left.length &&
    start < right.length &&
    left[start] === right[start]
  ) {
    start += 1;
  }
  let end = 0;
  while (
    end < left.length - start &&
    end < right.length - start &&
    left[left.length - 1 - end] === right[right.length - 1 - end]
  ) {
    end += 1;
  }
  const a = left.slice(start, left.length - end);
  const b = right.slice(start, right.length - end);
  const middle: OlympusDiffLine[] = [];
  if (a.length * b.length > LINE_DIFF_MAX_CELLS) {
    for (const text of a) middle.push({ type: "del", text });
    for (const text of b) middle.push({ type: "add", text });
  } else {
    const lcs = Array.from({ length: a.length + 1 }, () =>
      new Array<number>(b.length + 1).fill(0),
    );
    for (let i = a.length - 1; i >= 0; i -= 1) {
      for (let j = b.length - 1; j >= 0; j -= 1) {
        lcs[i][j] =
          a[i] === b[j]
            ? lcs[i + 1][j + 1] + 1
            : Math.max(lcs[i + 1][j], lcs[i][j + 1]);
      }
    }
    let i = 0;
    let j = 0;
    while (i < a.length || j < b.length) {
      if (i < a.length && j < b.length && a[i] === b[j]) {
        middle.push({ type: "same", text: a[i] });
        i += 1;
        j += 1;
      } else if (
        j < b.length &&
        (i === a.length || lcs[i][j + 1] > lcs[i + 1][j])
      ) {
        middle.push({ type: "add", text: b[j] });
        j += 1;
      } else {
        middle.push({ type: "del", text: a[i] });
        i += 1;
      }
    }
  }
  return [
    ...left.slice(0, start).map((text) => ({ type: "same" as const, text })),
    ...middle,
    ...left
      .slice(left.length - end)
      .map((text) => ({ type: "same" as const, text })),
  ];
}
