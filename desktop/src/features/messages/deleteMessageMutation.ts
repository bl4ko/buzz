import {
  type MutateOptions,
  type QueryClient,
  type QueryKey,
  type UseMutationResult,
  useMutation,
  useQueryClient,
} from "@tanstack/react-query";
import { toast } from "sonner";

import {
  emptyChannelWindowStore,
  type ChannelWindowStore,
} from "./lib/channelWindowStore";
import { channelMessagesKey, channelWindowKey } from "./lib/messageQueryKeys";
import { deleteMessage } from "@/shared/api/tauri";
import type { Channel, RelayEvent } from "@/shared/api/types";
import { KIND_DELETION } from "@/shared/constants/kinds";

type DeleteInput = { eventId: string };
type DeleteVariables = DeleteInput & { channelId: string | null };
type DeleteContext = {
  channelId: string;
  marker: RelayEvent;
  stopWatching: () => void;
  isCurrentScope: () => boolean;
};

function isEventQuery(key: QueryKey, channelId: string) {
  return (
    key[1] === channelId &&
    (key[0] === "channel-messages" || key[0] === "thread-replies")
  );
}

function updateEventCaches(
  client: QueryClient,
  channelId: string,
  marker: RelayEvent | null,
  removedId?: string,
  deletedId?: string,
) {
  const queries = client.getQueriesData<RelayEvent[]>({
    predicate: (query) => isEventQuery(query.queryKey, channelId),
  });
  for (const [key, events] of queries) {
    if (!events) continue;
    const filtered = events.filter(
      (event) => event.id !== removedId && event.id !== deletedId,
    );
    const next =
      marker && !filtered.some((event) => event.id === marker.id)
        ? [...filtered, marker]
        : filtered;
    if (
      next.length !== events.length ||
      next.some((event, index) => event !== events[index])
    ) {
      client.setQueryData(key, next);
    }
  }
}

function updateWindow(
  client: QueryClient,
  channelId: string,
  marker: RelayEvent | null,
  removedId?: string,
  deletedId?: string,
) {
  client.setQueryData<ChannelWindowStore>(
    channelWindowKey(channelId),
    (current = emptyChannelWindowStore()) => {
      const keep = (event: RelayEvent) =>
        event.id !== removedId && event.id !== deletedId;
      const liveSummaries = { ...current.liveSummaries };
      if (deletedId) delete liveSummaries[deletedId];
      const liveAux = current.liveAux.filter(keep);
      if (marker && !liveAux.some((event) => event.id === marker.id)) {
        liveAux.push(marker);
      }
      return {
        ...current,
        pages: current.pages.map((page) => ({
          ...page,
          rows: page.rows.filter((row) => keep(row.event)),
          aux: page.aux.filter(keep),
        })),
        liveOverlay: current.liveOverlay.filter(keep),
        liveAux,
        liveSummaries,
      };
    },
  );
}

export function useDeleteMessageMutation(
  channel: Channel | null,
): UseMutationResult<RelayEvent, Error, DeleteInput, DeleteContext> {
  const queryClient = useQueryClient();
  const mutation = useMutation<
    RelayEvent,
    Error,
    DeleteVariables,
    DeleteContext
  >({
    mutationFn: ({ eventId, channelId }) => {
      if (!channelId) throw new Error("No channel selected.");
      return deleteMessage(channelId, eventId);
    },
    onMutate: async ({ eventId, channelId }) => {
      if (!channelId) throw new Error("No channel selected.");
      const cache = queryClient.getQueryCache();
      const queryKey = channelMessagesKey(channelId);
      const channelQuery = cache.find({ queryKey, exact: true });
      const isCurrentScope = () =>
        channelQuery !== undefined &&
        cache.find({ queryKey, exact: true }) === channelQuery;
      await queryClient.cancelQueries({
        predicate: (query) => isEventQuery(query.queryKey, channelId),
      });
      if (!isCurrentScope()) throw new Error("Channel changed.");

      const marker: RelayEvent = {
        id: `optimistic-delete-${crypto.randomUUID()}`,
        pubkey: "",
        created_at: Math.floor(Date.now() / 1_000),
        kind: KIND_DELETION,
        tags: [
          ["h", channelId],
          ["e", eventId],
        ],
        content: "",
        sig: "",
        pending: true,
      };
      updateWindow(queryClient, channelId, marker);
      updateEventCaches(queryClient, channelId, marker);
      const stopWatching = cache.subscribe((event) => {
        if (event.type === "removed" && event.query === channelQuery) {
          stopWatching();
          return;
        }
        if (
          event.type === "updated" &&
          isEventQuery(event.query.queryKey, channelId)
        ) {
          updateEventCaches(queryClient, channelId, marker);
        }
      });
      return { channelId, marker, stopWatching, isCurrentScope };
    },
    onSuccess: (accepted, { eventId }, context) => {
      if (!context) return;
      context.stopWatching();
      if (!context.isCurrentScope()) return;
      updateWindow(
        queryClient,
        context.channelId,
        accepted,
        context.marker.id,
        eventId,
      );
      updateEventCaches(
        queryClient,
        context.channelId,
        accepted,
        context.marker.id,
        eventId,
      );
    },
    onError: (error, _variables, context) => {
      context?.stopWatching();
      if (context?.isCurrentScope()) {
        updateWindow(queryClient, context.channelId, null, context.marker.id);
        updateEventCaches(
          queryClient,
          context.channelId,
          null,
          context.marker.id,
        );
      }
      toast.error(`Failed to delete message: ${error.message}`);
    },
  });

  type Options = MutateOptions<RelayEvent, Error, DeleteInput, DeleteContext>;
  const variables = (input: DeleteInput): DeleteVariables => ({
    ...input,
    channelId: channel?.id ?? null,
  });
  return {
    ...mutation,
    mutate: (input: DeleteInput, options?: Options) =>
      mutation.mutate(variables(input), options),
    mutateAsync: (input: DeleteInput, options?: Options) =>
      mutation.mutateAsync(variables(input), options),
  };
}
