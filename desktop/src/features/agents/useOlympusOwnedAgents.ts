import * as React from "react";

import {
  type OlympusOwnedAgent,
  olympusOwnedAgents,
  olympusOwnedAgentsKey,
} from "@/features/agents/lib/olympusOwnedAgents";
import { useOlympusAgents } from "@/features/agents/useOlympusAgents";

export function useOlympusOwnedAgents(): readonly OlympusOwnedAgent[] {
  const { groups, me } = useOlympusAgents();
  const agents = React.useMemo(
    () => olympusOwnedAgents(groups, me),
    [groups, me],
  );
  const key = olympusOwnedAgentsKey(agents);
  const stable = React.useRef({ key, agents });
  if (stable.current.key !== key) stable.current = { key, agents };
  return stable.current.agents;
}
