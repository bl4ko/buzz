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
import {
  listOlympusProposals,
  olympusOperators,
} from "@/features/agents/lib/olympusProposals";
import { useCommunities } from "@/features/communities/useCommunities";
import { useIdentityQuery } from "@/shared/api/hooks";
import { relayClient } from "@/shared/api/relayClient";
import { signRelayEvent } from "@/shared/api/tauri";
import type { RelayEvent } from "@/shared/api/types";
import { normalizePubkey } from "@/shared/lib/pubkey";
import { KIND_OLYMPUS_CHANGE_RESULT } from "@/shared/constants/kinds";
import {
  listOlympusHistory,
  mergeOlympusHistory,
} from "@/features/olympus/lib/olympusHistory";

const OLYMPUS_HISTORY_LIMIT = 1_000;
const OLYMPUS_LIVE_OVERLAP_SECONDS = 60;

const OLYMPUS_RESULT_HISTORY_LIMIT = 300;

export function olympusAgentsQueryKey(relayUrl: string, pubkey: string) {
  return ["olympus-agents", relayUrl, pubkey] as const;
}

export function olympusHistoryQueryKey(relayUrl: string, pubkey: string) {
  return ["olympus-history", relayUrl, pubkey] as const;
}

const relayOlympusChangeTransport: OlympusChangeTransport = {
  sign: (template) => signRelayEvent(template),
  subscribe: (filter, onEvent) =>
    relayClient.subscribeInteractive(filter, onEvent),
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
  historyKey: QueryKey,
) {
  const queryClient = useQueryClient();
  React.useEffect(() => {
    if (!enabled) return;
    let disposed = false;
    let dispose: (() => Promise<void>) | null = null;
    const ingest = (event: RelayEvent) => {
      if (event.kind === KIND_OLYMPUS_CHANGE_RESULT) {
        queryClient.setQueryData<RelayEvent[]>(historyKey, (current) =>
          mergeOlympusHistory(current ?? [], [event]),
        );
        return;
      }
      queryClient.setQueryData<RelayEvent[]>(queryKey, (current) =>
        mergeOlympusEvents(current ?? [], [event]),
      );
    };
    void relayClient
      .subscribeLive(
        {
          kinds: [...OLYMPUS_STATE_KINDS, KIND_OLYMPUS_CHANGE_RESULT],
          "#p": [pubkey],
          limit: OLYMPUS_HISTORY_LIMIT,
          since: Math.floor(Date.now() / 1_000) - OLYMPUS_LIVE_OVERLAP_SECONDS,
        },
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
      void queryClient.invalidateQueries({ queryKey: historyKey });
    });
    return () => {
      disposed = true;
      unsubscribeReconnect();
      if (dispose) void dispose();
    };
  }, [enabled, historyKey, pubkey, queryClient, queryKey]);
}

function useOlympusAgentsSource(active: boolean) {
  const queryClient = useQueryClient();
  const identityQuery = useIdentityQuery();
  const { activeCommunity } = useCommunities();
  const pubkey = normalizePubkey(identityQuery.data?.pubkey ?? "");
  const relayUrl = activeCommunity?.relayUrl ?? "";
  const enabled = active && pubkey.length > 0 && relayUrl.length > 0;
  const queryKey = React.useMemo(
    () => olympusAgentsQueryKey(relayUrl, pubkey),
    [relayUrl, pubkey],
  );
  const historyKey = React.useMemo(
    () => olympusHistoryQueryKey(relayUrl, pubkey),
    [relayUrl, pubkey],
  );

  useOlympusLiveEvents(enabled, pubkey, queryKey, historyKey);

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

  const historyQuery = useQuery({
    enabled,
    queryKey: historyKey,
    queryFn: async () => {
      const events = await relayClient.fetchEvents({
        kinds: [KIND_OLYMPUS_CHANGE_RESULT],
        "#p": [pubkey],
        limit: OLYMPUS_RESULT_HISTORY_LIMIT,
      });
      return mergeOlympusHistory(
        queryClient.getQueryData<RelayEvent[]>(historyKey) ?? [],
        events,
      );
    },
    staleTime: 60_000,
  });

  const events = query.data ?? EMPTY_EVENTS;
  const groups = React.useMemo(() => groupOlympusAgents(events), [events]);
  const operators = React.useMemo(() => olympusOperators(groups), [groups]);
  const proposals = React.useMemo(
    () => listOlympusProposals(events, operators),
    [events, operators],
  );
  const history = React.useMemo(
    () => listOlympusHistory(historyQuery.data ?? EMPTY_EVENTS, operators),
    [historyQuery.data, operators],
  );

  const submitChange = React.useCallback(
    (key: string, target: OlympusChangeTarget, change: OlympusChange) =>
      submitOlympusChange(
        { key, me: pubkey, target, change },
        relayOlympusChangeTransport,
      ),
    [pubkey],
  );

  return React.useMemo(
    () => ({
      events,
      groups,
      history,
      error: query.error instanceof Error ? query.error : null,
      isLoading: enabled && query.isLoading,
      enabled,
      me: pubkey,
      proposals,
      submitChange,
    }),
    [
      enabled,
      events,
      groups,
      history,
      proposals,
      pubkey,
      query.error,
      query.isLoading,
      submitChange,
    ],
  );
}

const EMPTY_EVENTS: RelayEvent[] = [];

export type OlympusAgentsState = ReturnType<typeof useOlympusAgentsSource>;

const OlympusAgentsContext = React.createContext<OlympusAgentsState | null>(
  null,
);

export function OlympusAgentsProvider({
  children,
}: {
  children: React.ReactNode;
}) {
  const state = useOlympusAgentsSource(true);
  return React.createElement(
    OlympusAgentsContext.Provider,
    { value: state },
    children,
  );
}

export function useOlympusAgents(): OlympusAgentsState {
  const shared = React.useContext(OlympusAgentsContext);
  const own = useOlympusAgentsSource(shared === null);
  return shared ?? own;
}
