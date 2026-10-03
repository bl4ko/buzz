import { type QueryClient, queryOptions } from "@tanstack/react-query";
import { getChannelWindowEvents } from "@/shared/api/channelWindow";
import { storeChannelHeadCache } from "@/shared/api/tauriChannelHeadCache";
import type { Channel, RelayEvent } from "@/shared/api/types";
import {
  channelHeadCacheScope,
  channelHeadHydration,
  consumeHydratedChannel,
} from "./channelHeadCache";
import { parseChannelWindowResponse } from "./channelWindowResponse";
import {
  type ChannelWindowStore,
  emptyChannelWindowStore,
  replaceNewestChannelWindow,
} from "./channelWindowStore";
import { reconcileChannelWindowMessages } from "./channelWindowReconciliation";
import { channelMessagesKey, channelWindowKey } from "./messageQueryKeys";

export function reconcileFetchedChannelWindow(
  queryClient: QueryClient,
  channelId: string,
  events: Awaited<ReturnType<typeof getChannelWindowEvents>>,
  previousMessages: RelayEvent[],
  signal: AbortSignal,
): RelayEvent[] {
  signal.throwIfAborted();
  const windowKey = channelWindowKey(channelId);
  const page = parseChannelWindowResponse(events, channelId, null);
  const current =
    queryClient.getQueryData<ChannelWindowStore>(windowKey) ??
    emptyChannelWindowStore();
  const next = replaceNewestChannelWindow(current, page);
  queryClient.setQueryData(windowKey, next);
  const scope = channelHeadCacheScope(queryClient);
  if (scope) {
    void storeChannelHeadCache(scope, channelId, events).catch((error) => {
      console.warn("Failed to persist channel head", channelId, error);
    });
  }
  return reconcileChannelWindowMessages(next, previousMessages);
}

export function channelMessagesQueryOptions(
  queryClient: QueryClient,
  channelId: string,
) {
  const queryKey = channelMessagesKey(channelId);
  return queryOptions({
    queryKey,
    queryFn: async ({ signal }) => {
      await channelHeadHydration(queryClient);
      signal.throwIfAborted();
      if (consumeHydratedChannel(queryClient, channelId)) {
        return queryClient.getQueryData<RelayEvent[]>(queryKey) ?? [];
      }
      const previousMessages =
        queryClient.getQueryData<RelayEvent[]>(queryKey) ?? [];
      const events = await getChannelWindowEvents(channelId);
      return reconcileFetchedChannelWindow(
        queryClient,
        channelId,
        events,
        previousMessages,
        signal,
      );
    },
    staleTime: 5 * 60 * 1_000,
    gcTime: 60 * 60 * 1_000,
  });
}

const prefetches = new WeakMap<QueryClient, Set<string>>();

export async function prefetchChannelMessages(
  queryClient: QueryClient,
  channel: Channel,
): Promise<void> {
  if (!channel.isMember || channel.channelType === "forum") return;
  let active = prefetches.get(queryClient);
  if (!active) {
    active = new Set();
    prefetches.set(queryClient, active);
  }
  if (active.has(channel.id) || active.size >= 2) return;
  active.add(channel.id);
  try {
    await queryClient.prefetchQuery(
      channelMessagesQueryOptions(queryClient, channel.id),
    );
  } finally {
    active.delete(channel.id);
  }
}
