import type {
  OlympusAgent,
  OlympusCondition,
  OlympusWorkspaceGroup,
} from "@/features/agents/lib/olympusAgents";

export type OlympusProfileMatch = {
  agent: OlympusAgent;
  group: OlympusWorkspaceGroup;
};

export function findOwnedOlympusAgent(
  groups: readonly OlympusWorkspaceGroup[],
  me: string | null | undefined,
  pubkey: string | null | undefined,
): OlympusProfileMatch | null {
  const owner = me?.toLowerCase();
  const key = pubkey?.toLowerCase();
  if (!owner || !key) return null;
  let match: OlympusProfileMatch | null = null;
  for (const group of groups) {
    for (const agent of group.agents) {
      if (agent.publicKey !== key || agent.owner !== owner) continue;
      if (!match || agent.createdAt > match.agent.createdAt) {
        match = { agent, group };
      }
    }
  }
  return match;
}

export function olympusLastError(
  conditions: readonly OlympusCondition[],
): { title: string; detail: string | null } | null {
  const failing = conditions.find((condition) => condition.status === "False");
  if (!failing) return null;
  const title = failing.reason ?? failing.type;
  const detail =
    failing.message && failing.message !== title ? failing.message : null;
  return { title, detail };
}
