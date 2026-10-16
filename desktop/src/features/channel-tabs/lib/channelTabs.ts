import type { RelayEvent } from "@/shared/api/types";
import { KIND_CHANNEL_TABS } from "@/shared/constants/kinds";

export const CUSTOM_TAB_TYPES = ["link", "search", "thread", "canvas"] as const;
export type CustomTabType = (typeof CUSTOM_TAB_TYPES)[number];
export type ChannelTab = {
  id: string;
  type: string;
  title: string;
  value: string;
};
export type KnownChannelTab = ChannelTab & { type: CustomTabType };
const SLUG = /^[A-Za-z0-9_-]{1,64}$/;
const HEX64 = /^[0-9a-f]{64}$/;

function isTab(value: unknown): value is ChannelTab {
  if (!value || typeof value !== "object") return false;
  const tab = value as Record<string, unknown>;
  return (
    typeof tab.id === "string" &&
    SLUG.test(tab.id) &&
    typeof tab.type === "string" &&
    tab.type.length > 0 &&
    tab.type.length <= 32 &&
    typeof tab.title === "string" &&
    tab.title.trim() !== "" &&
    [...tab.title].length <= 40 &&
    typeof tab.value === "string" &&
    new TextEncoder().encode(tab.value).length <= 2048
  );
}

export function parseChannelTabs(content: string): ChannelTab[] | null {
  let value: unknown;
  try {
    value = JSON.parse(content);
  } catch {
    return null;
  }
  if (!Array.isArray(value) || value.length > 50 || !value.every(isTab))
    return null;
  const ids = new Set(value.map((tab) => tab.id));
  return ids.size === value.length
    ? value.map(({ id, type, title, value: v }) => ({
        id,
        type,
        title,
        value: v,
      }))
    : null;
}

export function latestChannelTabs(
  events: readonly RelayEvent[],
  channelId: string,
  canEdit: (pubkey: string) => boolean,
): { tabs: ChannelTab[]; eventId: string | null } {
  let best: RelayEvent | null = null;
  let bestTabs: ChannelTab[] = [];
  for (const event of events) {
    if (event.kind !== KIND_CHANNEL_TABS || !canEdit(event.pubkey)) continue;
    const d = event.tags.find((t) => t[0] === "d")?.[1];
    const h = event.tags.find((t) => t[0] === "h")?.[1];
    if (d !== channelId || h !== channelId) continue;
    const tabs = parseChannelTabs(event.content);
    if (!tabs) continue;
    const newer =
      !best ||
      event.created_at > best.created_at ||
      (event.created_at === best.created_at && event.id < best.id);
    if (newer) {
      best = event;
      bestTabs = tabs;
    }
  }
  return { tabs: bestTabs, eventId: best?.id ?? null };
}

export function knownTabs(tabs: readonly ChannelTab[]): KnownChannelTab[] {
  return tabs.filter((tab): tab is KnownChannelTab =>
    (CUSTOM_TAB_TYPES as readonly string[]).includes(tab.type),
  );
}

export function validateTabValue(
  type: CustomTabType,
  value: string,
): string | null {
  const trimmed = value.trim();
  if (type === "link") {
    try {
      return new URL(trimmed).protocol === "https:"
        ? null
        : "Use an https link.";
    } catch {
      return "Enter a full https link.";
    }
  }
  if (type === "search")
    return trimmed !== "" && trimmed.length <= 200
      ? null
      : "Enter a search of 1 to 200 characters.";
  if (type === "thread")
    return HEX64.test(trimmed) ? null : "Enter a thread root event ID.";
  return SLUG.test(trimmed) ? null : "Use letters, digits, - or _.";
}

export function newTabId(): string {
  return crypto.randomUUID().replaceAll("-", "").slice(0, 16);
}

export function addTab(
  tabs: readonly ChannelTab[],
  tab: ChannelTab,
): ChannelTab[] {
  return [...tabs, tab];
}

export function renameTab(
  tabs: readonly ChannelTab[],
  id: string,
  title: string,
): ChannelTab[] {
  return tabs.map((tab) => (tab.id === id ? { ...tab, title } : tab));
}

export function removeTab(
  tabs: readonly ChannelTab[],
  id: string,
): ChannelTab[] {
  return tabs.filter((tab) => tab.id !== id);
}

export function moveTab(
  tabs: readonly ChannelTab[],
  id: string,
  delta: -1 | 1,
): ChannelTab[] {
  const index = tabs.findIndex((tab) => tab.id === id);
  const target = index + delta;
  if (index < 0 || target < 0 || target >= tabs.length) return [...tabs];
  const next = [...tabs];
  [next[index], next[target]] = [next[target], next[index]];
  return next;
}

export function serializeChannelTabs(tabs: readonly ChannelTab[]): string {
  return JSON.stringify(
    tabs.map(({ id, type, title, value }) => ({ id, type, title, value })),
  );
}

export function channelTabTags(channelId: string): string[][] {
  return [
    ["d", channelId],
    ["h", channelId],
  ];
}
