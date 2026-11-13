import type { OlympusWorkspaceGroup } from "./olympusAgents";

export type OlympusOwnedAgent = {
  pubkey: string;
  name: string;
  status: "deployed" | "stopped";
};

export function olympusOwnedAgents(
  groups: readonly OlympusWorkspaceGroup[],
  me: string | null | undefined,
): OlympusOwnedAgent[] {
  const owner = me?.toLowerCase();
  if (!owner) return [];
  const byKey = new Map<string, OlympusOwnedAgent>();
  for (const group of groups) {
    for (const agent of group.agents) {
      if (!agent.publicKey || agent.owner !== owner) continue;
      if (byKey.has(agent.publicKey)) continue;
      byKey.set(agent.publicKey, {
        pubkey: agent.publicKey,
        name: agent.spec.profile?.displayName?.trim() || agent.name,
        status: agent.phase === "Suspended" ? "stopped" : "deployed",
      });
    }
  }
  return [...byKey.values()].sort((left, right) =>
    left.pubkey.localeCompare(right.pubkey),
  );
}

export function olympusOwnedAgentsKey(agents: readonly OlympusOwnedAgent[]) {
  return agents
    .map((agent) => `${agent.pubkey}:${agent.status}:${agent.name}`)
    .join(",");
}
