import type {
  OlympusAgent,
  OlympusWorkspaceGroup,
} from "@/features/agents/lib/olympusAgents";
import type { Channel, UserProfileSummary } from "@/shared/api/types";

export const MASTER_AGENT_ROLE = "master";
const MAX_QUOTE_LENGTH = 8_000;

export type AskMasterSeed = {
  quote?: string | null;
  link?: string | null;
};

export function findMasterAgent(
  groups: readonly OlympusWorkspaceGroup[],
): OlympusAgent | null {
  const masters = groups
    .flatMap((group) => group.agents)
    .filter((agent) => agent.role === MASTER_AGENT_ROLE && agent.publicKey);
  masters.sort(
    (left, right) =>
      Number(left.phase === "Suspended") -
        Number(right.phase === "Suspended") ||
      left.workspace.localeCompare(right.workspace) ||
      left.name.localeCompare(right.name),
  );
  return masters[0] ?? null;
}

export function masterAgentLabel(
  agent: OlympusAgent,
  profile: UserProfileSummary | null | undefined,
): string {
  return (
    profile?.displayName?.trim() ||
    agent.spec.profile?.displayName?.trim() ||
    profile?.name?.trim() ||
    agent.name
  );
}

export function masterAgentPicture(
  agent: OlympusAgent,
  profile: UserProfileSummary | null | undefined,
): string | null {
  return profile?.avatarUrl ?? agent.spec.profile?.picture ?? null;
}

export function findMasterDm(
  channels: readonly Channel[],
  me: string,
  master: string,
): Channel | null {
  const self = me.toLowerCase();
  const other = master.toLowerCase();
  return (
    channels.find((channel) => {
      if (channel.channelType !== "dm") return false;
      const keys = channel.participantPubkeys.map((key) => key.toLowerCase());
      return keys.length === 2 && keys.includes(self) && keys.includes(other);
    }) ?? null
  );
}

export function quoteMarkdown(text: string): string {
  const trimmed = text.replace(/\r\n?/g, "\n").trim();
  const clipped =
    trimmed.length > MAX_QUOTE_LENGTH
      ? `${trimmed.slice(0, MAX_QUOTE_LENGTH).trimEnd()}…`
      : trimmed;
  return clipped
    .split("\n")
    .map((line) => (line.trim() ? `> ${line.trimEnd()}` : ">"))
    .join("\n");
}

export function buildAskDraft(seed: AskMasterSeed): string {
  const parts: string[] = [];
  if (seed.quote?.trim()) parts.push(quoteMarkdown(seed.quote));
  if (seed.link) parts.push(`${seed.link} `);
  else if (parts.length > 0) parts.push("&nbsp;");
  return parts.join("\n\n");
}

export function mergeAskDraft(existing: string | undefined, next: string) {
  const current = (existing ?? "")
    .replace(/\s*(&nbsp;|\u00a0)\s*$/, "")
    .trimEnd();
  if (!current) return next;
  if (!next || current.includes(next.trim())) return current;
  return `${current}\n\n${next}`;
}
