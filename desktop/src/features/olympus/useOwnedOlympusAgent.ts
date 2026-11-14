import * as React from "react";

import { useOlympusAgents } from "@/features/agents/useOlympusAgents";
import {
  findOwnedOlympusAgent,
  type OlympusProfileMatch,
} from "./lib/olympusProfile";

export function useOwnedOlympusAgent(
  pubkey: string | null | undefined,
): OlympusProfileMatch | null {
  const { groups, me } = useOlympusAgents();
  return React.useMemo(
    () => findOwnedOlympusAgent(groups, me, pubkey),
    [groups, me, pubkey],
  );
}
