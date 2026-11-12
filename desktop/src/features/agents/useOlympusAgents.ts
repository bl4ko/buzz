import * as React from "react";
import { type QueryKey, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  groupOlympusAgents,
  mergeOlympusEvents,
  OLYMPUS_STATE_KINDS,
} from "@/features/agents/lib/olympusAgents";
import {
  type OlympusChange,
  type OlympusChangeTarget,
  type OlympusChangeTransport,
  submitOlympusChange,
} from "@/features/agents/lib/olympusChangeRequests";
import { useCommunities } from "@/features/communities/useCommunities";
import { useIdentityQuery } from "@/shared/api/hooks";
import { relayClient } from "@/shared/api/relayClient";
import { signRelayEvent } from "@/shared/api/tauri";
import type { RelayEvent } from "@/shared/api/types";
import { normalizePubkey } from "@/shared/lib/pubkey";

const OLYMPUS_HISTORY_LIMIT = 1_000;

export function olympusAgentsQueryKey(relayUrl: string, pubkey: string) {
  return ["olympus-agents", relayUrl, pubkey] as const;
}

const relayOlympusChangeTransport: OlympusChangeTransport = {
  sign: (template) => signRelayEvent(template),
  subscribe: (filter, onEvent) => relayClient.subscribeLive(filter, onEvent),
  publish: (event) =>
    relayClient.publishEvent(
      event,
      "Timed out while sending the change request.",
      "Failed to send the change request.",
    ),
};

function useOlympusLiveEvents(
  enabled: boolean,
  pubkey: string,
  queryKey: QueryKey,
) {
  const queryClient = useQueryClient();
  React.useEffect(() => {
    if (!enabled) return;
    let disposed = false;
    let dispose: (() => Promise<void>) | null = null;
    const ingest = (event: RelayEvent) => {
      queryClient.setQueryData<RelayEvent[]>(queryKey, (current) =>
        mergeOlympusEvents(current ?? [], [event]),
      );
    };
    void relayClient
      .subscribeLive(
        { kinds: [...OLYMPUS_STATE_KINDS], "#p": [pubkey], limit: 0 },
        ingest,
      )
      .then((unsubscribe) => {
        if (disposed) void unsubscribe();
        else dispose = unsubscribe;
      })
      .catch((error) => {
        console.error("Couldn’t subscribe to Olympus agents", error);
      });
    const unsubscribeReconnect = relayClient.subscribeToReconnects(() => {
      void queryClient.invalidateQueries({ queryKey });
    });
    return () => {
      disposed = true;
      unsubscribeReconnect();
      if (dispose) void dispose();
    };
  }, [enabled, pubkey, queryClient, queryKey]);
}

export function useOlympusAgents() {
  const queryClient = useQueryClient();
  const identityQuery = useIdentityQuery();
  const { activeCommunity } = useCommunities();
  const pubkey = normalizePubkey(identityQuery.data?.pubkey ?? "");
  const relayUrl = activeCommunity?.relayUrl ?? "";
  const enabled = pubkey.length > 0 && relayUrl.length > 0;
  const queryKey = React.useMemo(
    () => olympusAgentsQueryKey(relayUrl, pubkey),
    [relayUrl, pubkey],
  );

  useOlympusLiveEvents(enabled, pubkey, queryKey);

  const query = useQuery({
    enabled,
    queryKey,
    queryFn: async () => {
      const events = await relayClient.fetchEvents({
        kinds: [...OLYMPUS_STATE_KINDS],
        "#p": [pubkey],
        limit: OLYMPUS_HISTORY_LIMIT,
      });
      return mergeOlympusEvents(
        queryClient.getQueryData<RelayEvent[]>(queryKey) ?? [],
        events,
      );
    },
    staleTime: 60_000,
  });

  const groups = React.useMemo(
    () => groupOlympusAgents(query.data ?? []),
    [query.data],
  );

  const submitChange = React.useCallback(
    (key: string, target: OlympusChangeTarget, change: OlympusChange) =>
      submitOlympusChange(
        { key, me: pubkey, target, change },
        relayOlympusChangeTransport,
      ),
    [pubkey],
  );

  return {
    groups,
    error: query.error instanceof Error ? query.error : null,
    isLoading: enabled && query.isLoading,
    me: pubkey,
    submitChange,
  };
}

export type OlympusAgentsState = ReturnType<typeof useOlympusAgents>;
