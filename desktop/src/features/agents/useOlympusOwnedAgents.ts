import * as React from "react";

import {
  type OlympusOwnedAgent,
  olympusOwnedAgents,
  olympusOwnedAgentsKey,
} from "@/features/agents/lib/olympusOwnedAgents";
import { useOlympusAgents } from "@/features/agents/useOlympusAgents";
import { useUsersBatchQuery } from "@/features/profile/hooks";

export function useOlympusOwnedAgents(): readonly OlympusOwnedAgent[] {
  const { groups, me } = useOlympusAgents();
  const owned = React.useMemo(
    () => olympusOwnedAgents(groups, me),
    [groups, me],
  );
  const pubkeys = React.useMemo(
    () => owned.map((agent) => agent.pubkey),
    [owned],
  );
  const profiles = useUsersBatchQuery(pubkeys, {
    enabled: pubkeys.length > 0,
  }).data?.profiles;
  const agents = React.useMemo(
    () => olympusOwnedAgents(groups, me, profiles),
    [groups, me, profiles],
  );
  const key = olympusOwnedAgentsKey(agents);
  const stable = React.useRef({ key, agents });
  if (stable.current.key !== key) stable.current = { key, agents };
  return stable.current.agents;
}
