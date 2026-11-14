import {
  type OlympusWorkspace,
  type OlympusWorkspaceGroup,
  olympusEffectiveSpec,
  olympusModelOptions,
} from "@/features/agents/lib/olympusAgents";

export function olympusModelChoices(
  groups: readonly OlympusWorkspaceGroup[],
  workspace: OlympusWorkspace | null,
  pool: string,
): { restricted: boolean; models: string[] } {
  const allowed = olympusModelOptions(workspace, pool);
  if (allowed.length > 0) return { restricted: true, models: allowed };
  const seen = new Set<string>();
  for (const group of groups) {
    for (const agent of group.agents) {
      const spec = olympusEffectiveSpec(agent);
      if (spec.pool === pool && spec.model) seen.add(spec.model);
    }
    for (const template of group.workspace?.templates ?? []) {
      if (template.pool === pool && template.model) seen.add(template.model);
    }
  }
  return { restricted: false, models: [...seen].sort() };
}
