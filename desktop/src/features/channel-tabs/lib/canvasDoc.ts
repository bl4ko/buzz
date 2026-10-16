import type { RelayEvent } from "@/shared/api/types";
import { KIND_CHANNEL_CANVAS_DOC } from "@/shared/constants/kinds";

export const CANVAS_DOC_MAX_BYTES = 65_536;
export type CanvasVersion = {
  eventId: string;
  author: string;
  createdAt: number;
  content: string;
};

export function canvasDTag(channelId: string, canvasId: string) {
  return `${channelId}:${canvasId}`;
}

export function canvasTags(channelId: string, canvasId: string): string[][] {
  return [
    ["d", canvasDTag(channelId, canvasId)],
    ["h", channelId],
  ];
}

export function canvasByteLength(content: string) {
  return new TextEncoder().encode(content).length;
}

export function latestCanvas(
  events: readonly RelayEvent[],
  channelId: string,
  canvasId: string,
): CanvasVersion | null {
  let best: RelayEvent | null = null;
  const d = canvasDTag(channelId, canvasId);
  for (const event of events) {
    if (event.kind !== KIND_CHANNEL_CANVAS_DOC) continue;
    if (
      event.tags.find((t) => t[0] === "d")?.[1] !== d ||
      event.tags.find((t) => t[0] === "h")?.[1] !== channelId
    )
      continue;
    if (
      !best ||
      event.created_at > best.created_at ||
      (event.created_at === best.created_at && event.id < best.id)
    )
      best = event;
  }
  return best
    ? {
        eventId: best.id,
        author: best.pubkey,
        createdAt: best.created_at,
        content: best.content,
      }
    : null;
}

export function canvasConflict(
  baseEventId: string | null,
  latest: CanvasVersion | null,
): CanvasVersion | null {
  return latest && latest.eventId !== baseEventId ? latest : null;
}
