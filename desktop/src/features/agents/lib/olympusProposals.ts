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
  result: { reason: string | null; request: string | null } | null;
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
