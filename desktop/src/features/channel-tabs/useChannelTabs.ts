import * as React from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";

import type { RelayEvent } from "@/shared/api/types";
import { KIND_CHANNEL_TABS } from "@/shared/constants/kinds";
import {
  type ChannelEventTransport,
  mergeEvent,
  relayChannelEventTransport,
  useLiveChannelEvents,
} from "./channelEventTransport";
import {
  type ChannelTab,
  channelTabTags,
  type KnownChannelTab,
  knownTabs,
  latestChannelTabs,
  serializeChannelTabs,
} from "./lib/channelTabs";

const defaultTransport = relayChannelEventTransport("channel tabs");

export function channelTabsKey(channelId: string) {
  return ["channel-tabs", channelId] as const;
}

export type ChannelTabsState = {
  channelId: string;
  tabs: ChannelTab[];
  visible: KnownChannelTab[];
  isLoading: boolean;
  save: (tabs: ChannelTab[]) => Promise<void>;
};

export function useChannelTabs(
  channelId: string | null,
  transport: ChannelEventTransport = defaultTransport,
): ChannelTabsState | null {
  const queryClient = useQueryClient();
  const key = channelTabsKey(channelId ?? "none");
  const query = useQuery({
    enabled: channelId !== null,
    queryKey: key,
    queryFn: () =>
      transport.fetchEvents({
        kinds: [KIND_CHANNEL_TABS],
        "#h": [channelId ?? ""],
        limit: 200,
      }),
    staleTime: Number.POSITIVE_INFINITY,
  });
  useLiveChannelEvents(
    channelId,
    channelId ? { kinds: [KIND_CHANNEL_TABS], "#h": [channelId] } : null,
    key,
    transport,
  );
  const latest = React.useMemo(
    () => latestChannelTabs(query.data ?? [], channelId ?? ""),
    [query.data, channelId],
  );
  const latestCreatedAt =
    query.data?.find((event) => event.id === latest.eventId)?.created_at ?? 0;
  const save = React.useCallback(
    async (tabs: ChannelTab[]) => {
      if (!channelId) return;
      const signed = await transport.signEvent({
        kind: KIND_CHANNEL_TABS,
        content: serializeChannelTabs(tabs),
        createdAt: Math.max(transport.now(), latestCreatedAt + 1),
        tags: channelTabTags(channelId),
      });
      await transport.publishEvent(signed);
      queryClient.setQueryData<RelayEvent[]>(
        channelTabsKey(channelId),
        (current = []) => mergeEvent(current, signed),
      );
    },
    [channelId, latestCreatedAt, queryClient, transport],
  );
  return React.useMemo(
    () =>
      channelId
        ? {
            channelId,
            tabs: latest.tabs,
            visible: knownTabs(latest.tabs),
            isLoading: query.isLoading,
            save,
          }
        : null,
    [channelId, latest.tabs, query.isLoading, save],
  );
}
