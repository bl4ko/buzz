import type { KnownChannelTab } from "./channelTabs";

export type ChannelTabKey =
  | "messages"
  | "tasks"
  | "pins"
  | "files"
  | `custom:${string}`;
export type ChannelTabItem = {
  key: ChannelTabKey;
  label: string;
  badge?: number;
  custom?: KnownChannelTab;
};

export function buildChannelTabItems(input: {
  taskCount: number;
  awaitingCount: number;
  pinCount: number;
  fileCount: number;
  customTabs: readonly KnownChannelTab[];
}): ChannelTabItem[] {
  const items: ChannelTabItem[] = [{ key: "messages", label: "Messages" }];
  if (input.taskCount > 0)
    items.push({
      key: "tasks",
      label: "Tasks",
      badge: input.awaitingCount > 0 ? input.awaitingCount : undefined,
    });
  if (input.pinCount > 0) items.push({ key: "pins", label: "Pins" });
  if (input.fileCount > 0)
    items.push({ key: "files", label: "Files and links" });
  for (const tab of input.customTabs)
    items.push({ key: `custom:${tab.id}`, label: tab.title, custom: tab });
  return items;
}

export function resolveSelectedTab(
  items: readonly ChannelTabItem[],
  selected: ChannelTabKey,
): ChannelTabKey {
  return items.some((item) => item.key === selected) ? selected : "messages";
}
