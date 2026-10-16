import * as React from "react";
import { useQueryClient } from "@tanstack/react-query";

import { relayClient } from "@/shared/api/relayClient";
import type { RelaySubscriptionFilter } from "@/shared/api/relayClientShared";
import { signRelayEvent } from "@/shared/api/tauri";
import type { RelayEvent } from "@/shared/api/types";

export type ChannelEventTransport = {
  fetchEvents: (filter: RelaySubscriptionFilter) => Promise<RelayEvent[]>;
  subscribeLive: (
    filter: RelaySubscriptionFilter,
    onEvent: (event: RelayEvent) => void,
  ) => Promise<() => unknown>;
  subscribeToReconnects: (listener: () => void) => () => void;
  signEvent: (input: {
    kind: number;
    content: string;
    createdAt?: number;
    tags: string[][];
  }) => Promise<RelayEvent>;
  publishEvent: (event: RelayEvent) => Promise<unknown>;
  now: () => number;
};

export function relayChannelEventTransport(
  label: string,
): ChannelEventTransport {
  return {
    fetchEvents: (filter) => relayClient.fetchEvents(filter),
    subscribeLive: (filter, onEvent) =>
      relayClient.subscribeLive(filter, onEvent),
    subscribeToReconnects: (listener) =>
      relayClient.subscribeToReconnects(listener),
    signEvent: (input) => signRelayEvent(input),
    publishEvent: (event) =>
      relayClient.publishEvent(
        event,
        `Timed out saving the ${label}.`,
        `Failed to save the ${label}.`,
      ),
    now: () => Math.floor(Date.now() / 1_000),
  };
}

export function mergeEvent(
  current: readonly RelayEvent[],
  event: RelayEvent,
): RelayEvent[] {
  return current.some((item) => item.id === event.id)
    ? [...current]
    : [...current, event];
}

export function useLiveChannelEvents(
  channelId: string | null,
  filter: Omit<RelaySubscriptionFilter, "limit" | "since"> | null,
  queryKey: readonly unknown[],
  transport: Pick<
    ChannelEventTransport,
    "subscribeLive" | "subscribeToReconnects" | "now"
  >,
) {
  const queryClient = useQueryClient();
  const filterKey = JSON.stringify(filter);
  const keyString = JSON.stringify(queryKey);
  React.useEffect(() => {
    if (!channelId || filterKey === "null") return;
    const key = JSON.parse(keyString) as unknown[];
    let disposed = false;
    let unsubscribe: (() => unknown) | undefined;
    transport
      .subscribeLive(
        {
          ...(JSON.parse(filterKey) as RelaySubscriptionFilter),
          limit: 0,
          since: transport.now(),
        },
        (event) => {
          if (!disposed)
            queryClient.setQueryData<RelayEvent[]>(key, (current = []) =>
              mergeEvent(current, event),
            );
        },
      )
      .then(
        (dispose) => {
          if (disposed) void dispose();
          else unsubscribe = dispose;
        },
        () => {},
      );
    const stop = transport.subscribeToReconnects(() => {
      void queryClient.invalidateQueries({ queryKey: key });
    });
    return () => {
      disposed = true;
      void unsubscribe?.();
      stop();
    };
  }, [channelId, filterKey, keyString, queryClient, transport]);
}
