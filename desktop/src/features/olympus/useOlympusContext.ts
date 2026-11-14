import * as React from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";

import { useOlympusAgents } from "@/features/agents/useOlympusAgents";
import { useCommunities } from "@/features/communities/useCommunities";
import { relayClient } from "@/shared/api/relayClient";
import { decryptAgentTurnMetric } from "@/shared/api/tauriObserver";
import type { RelayEvent } from "@/shared/api/types";
import { KIND_AGENT_TURN_METRIC } from "@/shared/constants/kinds";
import {
  latestOlympusContexts,
  type OlympusContextUse,
  parseOlympusContext,
} from "./lib/olympusContext";

const HISTORY_LIMIT = 40;

async function readContext(
  event: RelayEvent,
): Promise<OlympusContextUse | null> {
  try {
    return parseOlympusContext(await decryptAgentTurnMetric(event));
  } catch {
    return null;
  }
}

function merge(
  current: readonly OlympusContextUse[],
  next: readonly (OlympusContextUse | null)[],
): OlympusContextUse[] {
  return latestOlympusContexts([
    ...current,
    ...next.filter((entry): entry is OlympusContextUse => entry !== null),
  ]);
}

export function useOlympusContext(agentPubkey: string | null | undefined) {
  const { me } = useOlympusAgents();
  const queryClient = useQueryClient();
  const { activeCommunity } = useCommunities();
  const relayUrl = activeCommunity?.relayUrl ?? "";
  const agent = agentPubkey?.toLowerCase() ?? "";
  const enabled = me.length > 0 && agent.length > 0 && relayUrl.length > 0;
  const queryKey = React.useMemo(
    () => ["olympus-context", relayUrl, me, agent] as const,
    [relayUrl, me, agent],
  );

  React.useEffect(() => {
    if (!enabled) return;
    let disposed = false;
    let dispose: (() => Promise<void>) | null = null;
    void relayClient
      .subscribeLive(
        {
          kinds: [KIND_AGENT_TURN_METRIC],
          authors: [agent],
          "#p": [me],
          limit: HISTORY_LIMIT,
          since: Math.floor(Date.now() / 1_000),
        },
        (event: RelayEvent) => {
          void readContext(event).then((entry) => {
            if (!entry || disposed) return;
            queryClient.setQueryData<OlympusContextUse[]>(queryKey, (current) =>
              merge(current ?? [], [entry]),
            );
          });
        },
      )
      .then((unsubscribe) => {
        if (disposed) void unsubscribe();
        else dispose = unsubscribe;
      })
      .catch((error) => {
        console.error("Couldn’t subscribe to agent context use", error);
      });
    return () => {
      disposed = true;
      if (dispose) void dispose();
    };
  }, [agent, enabled, me, queryClient, queryKey]);

  return useQuery({
    enabled,
    queryKey,
    queryFn: async () => {
      const events = await relayClient.fetchEvents({
        kinds: [KIND_AGENT_TURN_METRIC],
        authors: [agent],
        "#p": [me],
        limit: HISTORY_LIMIT,
      });
      return merge(
        queryClient.getQueryData<OlympusContextUse[]>(queryKey) ?? [],
        await Promise.all(events.map(readContext)),
      );
    },
    staleTime: 60_000,
  });
}
