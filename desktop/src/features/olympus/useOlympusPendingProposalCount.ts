import * as React from "react";

import { isOlympusProposalOpen } from "@/features/agents/lib/olympusProposals";
import { useOlympusAgents } from "@/features/agents/useOlympusAgents";

const TICK_MS = 60_000;

export function useOlympusPendingProposalCount(): number {
  const { proposals } = useOlympusAgents();
  const [now, setNow] = React.useState(() => Math.floor(Date.now() / 1_000));
  React.useEffect(() => {
    const timer = setInterval(
      () => setNow(Math.floor(Date.now() / 1_000)),
      TICK_MS,
    );
    return () => clearInterval(timer);
  }, []);
  return proposals.filter((proposal) => isOlympusProposalOpen(proposal, now))
    .length;
}
