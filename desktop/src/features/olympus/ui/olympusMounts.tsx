import { Gauge, GitPullRequestArrow } from "lucide-react";

import { olympusProposalKey } from "@/features/agents/lib/olympusProposals";
import {
  OlympusProposalCard,
  useVisibleOlympusProposals,
} from "@/features/agents/ui/OlympusProposalCard";
import { useOlympusAgents } from "@/features/agents/useOlympusAgents";
import { OlympusEmptyState } from "./OlympusParts";

export function OlympusProposalsTab() {
  const olympus = useOlympusAgents();
  const proposals = useVisibleOlympusProposals(olympus.proposals);
  if (proposals.length === 0) {
    return (
      <OlympusEmptyState
        icon={GitPullRequestArrow}
        testId="olympus-proposals-empty"
        title="No open proposals"
      >
        <p>
          When Zeus proposes a change to an agent, a schedule, or a workspace,
          it shows here for your decision.
        </p>
      </OlympusEmptyState>
    );
  }
  return (
    <div className="space-y-3" data-testid="olympus-proposals">
      {proposals.map((proposal) => (
        <OlympusProposalCard
          key={olympusProposalKey(proposal)}
          proposal={proposal}
          submitChange={olympus.submitChange}
        />
      ))}
    </div>
  );
}

export function OlympusUsageTab() {
  return (
    <OlympusEmptyState
      icon={Gauge}
      testId="olympus-usage-empty"
      title="No usage data yet"
    >
      <p>
        Token use, runs, and failures for each agent show here when Hephaestus
        publishes usage events.
      </p>
    </OlympusEmptyState>
  );
}

export function OlympusAgentUsage(_props: {
  workspace: string;
  agent: string;
}) {
  return null;
}
