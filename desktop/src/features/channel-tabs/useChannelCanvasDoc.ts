import * as React from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";

import type { RelayEvent } from "@/shared/api/types";
import { KIND_CHANNEL_CANVAS_DOC } from "@/shared/constants/kinds";
import {
  type ChannelEventTransport,
  mergeEvent,
  relayChannelEventTransport,
  useLiveChannelEvents,
} from "./channelEventTransport";
import {
  CANVAS_DOC_MAX_BYTES,
  type CanvasVersion,
  canvasByteLength,
  canvasConflict,
  canvasDTag,
  canvasTags,
  latestCanvas,
} from "./lib/canvasDoc";

const defaultTransport = relayChannelEventTransport("canvas");

export type ChannelCanvasDocState = {
  latest: CanvasVersion | null;
  isLoading: boolean;
  save: (
    content: string,
    baseEventId: string | null,
    force?: boolean,
  ) => Promise<"saved" | "conflict">;
};

export function useChannelCanvasDoc(
  channelId: string | null,
  canvasId: string | null,
  transport: ChannelEventTransport = defaultTransport,
): ChannelCanvasDocState | null {
  const queryClient = useQueryClient();
  const d = channelId && canvasId ? canvasDTag(channelId, canvasId) : "";
  const key = ["channel-canvas-doc", d] as const;
  const query = useQuery({
    enabled: d !== "",
    queryKey: key,
    queryFn: () =>
      transport.fetchEvents({
        kinds: [KIND_CHANNEL_CANVAS_DOC],
        "#h": [channelId ?? ""],
        "#d": [d],
        limit: 50,
      }),
    staleTime: Number.POSITIVE_INFINITY,
  });
  useLiveChannelEvents(
    channelId,
    d
      ? { kinds: [KIND_CHANNEL_CANVAS_DOC], "#h": [channelId ?? ""], "#d": [d] }
      : null,
    key,
    transport,
  );
  const latest = React.useMemo(
    () =>
      channelId && canvasId
        ? latestCanvas(query.data ?? [], channelId, canvasId)
        : null,
    [query.data, channelId, canvasId],
  );
  const save = React.useCallback(
    async (content: string, baseEventId: string | null, force = false) => {
      if (!channelId || !canvasId) return "conflict" as const;
      if (canvasByteLength(content) > CANVAS_DOC_MAX_BYTES)
        throw new Error("Canvas is larger than 64 KB.");
      if (!force && canvasConflict(baseEventId, latest))
        return "conflict" as const;
      const signed = await transport.signEvent({
        kind: KIND_CHANNEL_CANVAS_DOC,
        content,
        createdAt: Math.max(transport.now(), (latest?.createdAt ?? 0) + 1),
        tags: canvasTags(channelId, canvasId),
      });
      await transport.publishEvent(signed);
      queryClient.setQueryData<RelayEvent[]>(
        ["channel-canvas-doc", canvasDTag(channelId, canvasId)],
        (current = []) => mergeEvent(current, signed),
      );
      return "saved" as const;
    },
    [channelId, canvasId, latest, queryClient, transport],
  );
  return channelId && canvasId
    ? { latest, isLoading: query.isLoading, save }
    : null;
}
