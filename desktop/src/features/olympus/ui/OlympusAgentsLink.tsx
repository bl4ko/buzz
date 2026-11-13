import { ChevronRight, MountainSnow } from "lucide-react";

import { useAppNavigation } from "@/app/navigation/useAppNavigation";
import { useOlympusAgents } from "@/features/agents/useOlympusAgents";

export function OlympusAgentsLink() {
  const olympus = useOlympusAgents();
  const { goOlympus } = useAppNavigation();
  const count = olympus.groups.reduce(
    (total, group) => total + group.agents.length,
    0,
  );
  if (count === 0) return null;
  return (
    <button
      className="flex w-full items-center gap-3 rounded-xl border border-border/70 bg-card/60 px-4 py-3 text-left transition-colors hover:bg-muted/40 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring"
      data-testid="olympus-agents-link"
      onClick={() => void goOlympus()}
      type="button"
    >
      <MountainSnow aria-hidden className="h-5 w-5 text-muted-foreground" />
      <span className="min-w-0 flex-1">
        <span className="block text-sm font-medium text-foreground">
          Olympus agents
        </span>
        <span className="block text-xs text-muted-foreground">
          {count} {count === 1 ? "agent runs" : "agents run"} in the cluster.
          Manage them on the Olympus page. This page shows the agents on this
          Mac.
        </span>
      </span>
      <ChevronRight aria-hidden className="h-4 w-4 text-muted-foreground" />
    </button>
  );
}
