import * as React from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";

import { olympusOperators } from "@/features/agents/lib/olympusProposals";
import {
  buildOlympusUsage,
  mergeOlympusUsageEvents,
} from "@/features/agents/lib/olympusUsage";
import { useOlympusAgents } from "@/features/agents/useOlympusAgents";
import { useCommunities } from "@/features/communities/useCommunities";
import { relayClient } from "@/shared/api/relayClient";
import type { RelayEvent } from "@/shared/api/types";
import { KIND_OLYMPUS_USAGE } from "@/shared/constants/kinds";

const USAGE_HISTORY_LIMIT = 500;
const USAGE_LIVE_OVERLAP_SECONDS = 60;

export function useOlympusUsage() {
  const olympus = useOlympusAgents();
  const queryClient = useQueryClient();
  const { activeCommunity } = useCommunities();
  const me = olympus.me;
  const relayUrl = activeCommunity?.relayUrl ?? "";
  const enabled = me.length > 0 && relayUrl.length > 0;
  const queryKey = React.useMemo(
    () => ["olympus-usage", relayUrl, me] as const,
    [relayUrl, me],
  );

  React.useEffect(() => {
    if (!enabled) return;
    let disposed = false;
    let dispose: (() => Promise<void>) | null = null;
    void relayClient
      .subscribeLive(
        {
          kinds: [KIND_OLYMPUS_USAGE],
          "#p": [me],
          limit: USAGE_HISTORY_LIMIT,
          since: Math.floor(Date.now() / 1_000) - USAGE_LIVE_OVERLAP_SECONDS,
        },
        (event: RelayEvent) => {
          queryClient.setQueryData<RelayEvent[]>(queryKey, (current) =>
            mergeOlympusUsageEvents(current ?? [], [event]),
          );
        },
      )
      .then((unsubscribe) => {
        if (disposed) void unsubscribe();
        else dispose = unsubscribe;
      })
      .catch((error) => {
        console.error("Couldn’t subscribe to Olympus usage", error);
      });
    const unsubscribeReconnect = relayClient.subscribeToReconnects(() => {
      void queryClient.invalidateQueries({ queryKey });
    });
    return () => {
      disposed = true;
      unsubscribeReconnect();
      if (dispose) void dispose();
    };
  }, [enabled, me, queryClient, queryKey]);

  const query = useQuery({
    enabled,
    queryKey,
    queryFn: async () =>
      mergeOlympusUsageEvents(
        queryClient.getQueryData<RelayEvent[]>(queryKey) ?? [],
        await relayClient.fetchEvents({
          kinds: [KIND_OLYMPUS_USAGE],
          "#p": [me],
          limit: USAGE_HISTORY_LIMIT,
        }),
      ),
    staleTime: 60_000,
  });

  const usage = React.useMemo(
    () => buildOlympusUsage(query.data ?? [], olympusOperators(olympus.groups)),
    [olympus.groups, query.data],
  );

  return {
    ...usage,
    groups: olympus.groups,
    error: query.error instanceof Error ? query.error : (olympus.error ?? null),
    isLoading: enabled && (query.isLoading || olympus.isLoading),
  };
}
