import * as React from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";

import {
  buildPinEventTags,
  deletionTargetIds,
  mergePinEvent,
  nextPinCreatedAt,
  type PinnedMessage,
  type PinRecord,
  parsePinEvent,
  reducePinEvents,
  selectPinnedMessages,
  selectPinnedRecords,
} from "@/features/messages/lib/messagePins";
import { relayClient } from "@/shared/api/relayClient";
import type { RelaySubscriptionFilter } from "@/shared/api/relayClientShared";
import { signRelayEvent } from "@/shared/api/tauri";
import type { RelayEvent } from "@/shared/api/types";
import {
  CHANNEL_MESSAGE_EVENT_KINDS,
  KIND_DELETION,
  KIND_NIP29_DELETE_EVENT,
  KIND_STREAM_MESSAGE_EDIT,
  KIND_STREAM_MESSAGE_PINNED,
} from "@/shared/constants/kinds";

const PIN_HISTORY_LIMIT = 10_000;
const TARGET_CHUNK_SIZE = 100;

export type ChannelPinTransport = {
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

export const relayChannelPinTransport: ChannelPinTransport = {
  fetchEvents: (filter) => relayClient.fetchEvents(filter),
  subscribeLive: (filter, onEvent) =>
    relayClient.subscribeLive(filter, onEvent),
  subscribeToReconnects: (listener) =>
    relayClient.subscribeToReconnects(listener),
  signEvent: (input) => signRelayEvent(input),
  publishEvent: (event) =>
    relayClient.publishEvent(
      event,
      "Timed out updating the pinned message.",
      "Failed to update the pinned message.",
    ),
  now: () => Math.floor(Date.now() / 1_000),
};

export function channelPinsKey(channelId: string) {
  return ["channel-pins", channelId] as const;
}

export type ChannelPinsState = {
  channelId: string;
  pins: ReadonlyMap<string, PinRecord>;
  pinnedMessages: PinnedMessage[];
  isLoading: boolean;
  isPinned: (messageId: string) => boolean;
  setPinned: (messageId: string, pinned: boolean) => Promise<void>;
};

function chunk<T>(items: readonly T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let index = 0; index < items.length; index += size) {
    chunks.push(items.slice(index, index + size));
  }
  return chunks;
}

function hasChannelTag(event: RelayEvent, channelId: string) {
  return event.tags.some((tag) => tag[0] === "h" && tag[1] === channelId);
}

async function fetchPinTargets(
  transport: ChannelPinTransport,
  channelId: string,
  targetIds: string[],
): Promise<Map<string, RelayEvent>> {
  const targets = new Map<string, RelayEvent>();
  const edits: RelayEvent[] = [];
  await Promise.all(
    chunk(targetIds, TARGET_CHUNK_SIZE).map(async (ids) => {
      const [events, editEvents] = await Promise.all([
        transport.fetchEvents({
          ids,
          kinds: [...CHANNEL_MESSAGE_EVENT_KINDS],
          limit: ids.length,
        }),
        transport.fetchEvents({
          kinds: [KIND_STREAM_MESSAGE_EDIT],
          "#e": ids,
          limit: PIN_HISTORY_LIMIT,
        }),
      ]);
      for (const event of events) {
        if (ids.includes(event.id) && hasChannelTag(event, channelId)) {
          targets.set(event.id, event);
        }
      }
      edits.push(...editEvents);
    }),
  );
  const latestEdit = new Map<string, RelayEvent>();
  for (const edit of edits) {
    const targetId = edit.tags.find((tag) => tag[0] === "e")?.[1];
    const target = targetId ? targets.get(targetId) : undefined;
    if (!targetId || !target || edit.pubkey !== target.pubkey) continue;
    const current = latestEdit.get(targetId);
    if (!current || edit.created_at > current.created_at) {
      latestEdit.set(targetId, edit);
    }
  }
  for (const [targetId, edit] of latestEdit) {
    const target = targets.get(targetId);
    if (target) targets.set(targetId, { ...target, content: edit.content });
  }
  return targets;
}

export function useChannelPins(
  channelId: string | null,
  transport: ChannelPinTransport = relayChannelPinTransport,
): ChannelPinsState | null {
  const queryClient = useQueryClient();
  const enabled = channelId !== null;
  const queryKey = channelPinsKey(channelId ?? "none");
  const [deletedTargetIds, setDeletedTargetIds] = React.useState<
    ReadonlySet<string>
  >(() => new Set());

  const eventsQuery = useQuery({
    enabled,
    queryKey,
    queryFn: () =>
      transport.fetchEvents({
        kinds: [KIND_STREAM_MESSAGE_PINNED],
        "#h": [channelId ?? ""],
        limit: PIN_HISTORY_LIMIT,
      }),
    staleTime: Number.POSITIVE_INFINITY,
  });
  const pinEvents = eventsQuery.data;

  React.useEffect(() => {
    setDeletedTargetIds(new Set());
    if (!channelId) return;
    let disposed = false;
    let unsubscribe: (() => unknown) | undefined;
    const key = channelPinsKey(channelId);
    const handleEvent = (event: RelayEvent) => {
      if (disposed) return;
      if (event.kind === KIND_STREAM_MESSAGE_PINNED) {
        if (!parsePinEvent(event)) return;
        queryClient.setQueryData<RelayEvent[]>(key, (current = []) =>
          mergePinEvent(current, event),
        );
        return;
      }
      const ids = deletionTargetIds(event);
      if (ids.length === 0) return;
      setDeletedTargetIds((current) => {
        const next = new Set(current);
        for (const id of ids) next.add(id);
        return next;
      });
    };
    transport
      .subscribeLive(
        {
          kinds: [
            KIND_STREAM_MESSAGE_PINNED,
            KIND_DELETION,
            KIND_NIP29_DELETE_EVENT,
          ],
          "#h": [channelId],
          limit: 0,
          since: transport.now(),
        },
        handleEvent,
      )
      .then(
        (dispose) => {
          if (disposed) {
            void dispose();
            return;
          }
          unsubscribe = dispose;
          void queryClient.invalidateQueries({ queryKey: key });
        },
        (error) => {
          console.error(
            "Failed to subscribe to channel pins",
            channelId,
            error,
          );
        },
      );
    const disposeReconnect = transport.subscribeToReconnects(() => {
      void queryClient.invalidateQueries({ queryKey: key });
    });
    return () => {
      disposed = true;
      disposeReconnect();
      if (unsubscribe) void unsubscribe();
    };
  }, [channelId, queryClient, transport]);

  const pins = React.useMemo(
    () => reducePinEvents(pinEvents ?? [], channelId ?? ""),
    [channelId, pinEvents],
  );
  const pinnedRecords = React.useMemo(() => selectPinnedRecords(pins), [pins]);
  const pinnedTargetIds = React.useMemo(
    () => [...new Set(pinnedRecords.map((record) => record.targetId))].sort(),
    [pinnedRecords],
  );

  const targetsQuery = useQuery({
    enabled: enabled && pinnedTargetIds.length > 0,
    queryKey: ["channel-pin-targets", channelId ?? "none", ...pinnedTargetIds],
    queryFn: () => fetchPinTargets(transport, channelId ?? "", pinnedTargetIds),
    placeholderData: (previous) => previous,
    staleTime: 60_000,
  });
  const targets = targetsQuery.data;

  const pinnedMessages = React.useMemo(
    () =>
      selectPinnedMessages(
        pinnedRecords,
        targets ?? new Map<string, RelayEvent>(),
        deletedTargetIds,
      ),
    [deletedTargetIds, pinnedRecords, targets],
  );

  const pinsRef = React.useRef(pins);
  pinsRef.current = pins;
  const setPinned = React.useCallback(
    async (messageId: string, pinned: boolean) => {
      if (!channelId) return;
      const event = await transport.signEvent({
        kind: KIND_STREAM_MESSAGE_PINNED,
        content: "",
        createdAt: nextPinCreatedAt(
          transport.now(),
          pinsRef.current.get(messageId),
        ),
        tags: buildPinEventTags(channelId, messageId, pinned),
      });
      await transport.publishEvent(event);
      queryClient.setQueryData<RelayEvent[]>(
        channelPinsKey(channelId),
        (current = []) => mergePinEvent(current, event),
      );
    },
    [channelId, queryClient, transport],
  );

  const isPinned = React.useCallback(
    (messageId: string) =>
      pins.get(messageId)?.status === "pinned" &&
      !deletedTargetIds.has(messageId),
    [deletedTargetIds, pins],
  );

  const isLoading =
    eventsQuery.isPending ||
    (pinnedTargetIds.length > 0 && targetsQuery.isPending);

  return React.useMemo(
    () =>
      channelId
        ? {
            channelId,
            pins,
            pinnedMessages,
            isLoading,
            isPinned,
            setPinned,
          }
        : null,
    [channelId, isLoading, isPinned, pinnedMessages, pins, setPinned],
  );
}
