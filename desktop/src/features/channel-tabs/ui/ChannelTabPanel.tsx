import type { ChannelTabKey } from "../lib/channelTabItems";
import type { KnownChannelTab } from "../lib/channelTabs";
import type { ChannelTasksState } from "../useChannelTasks";
import type { FileLinkItem } from "../lib/filesAndLinks";
import type { useChannelFilesAndLinks } from "../useChannelFilesAndLinks";
import { ChannelFilesTab } from "./ChannelFilesTab";
import { ChannelPinsTab } from "./ChannelPinsTab";
import { ChannelTasksTab } from "./ChannelTasksTab";
import { CustomTabPanel } from "./CustomTabPanel";

export function ChannelTabPanel({
  selected,
  channelId,
  currentPubkey,
  tasks,
  canSetStatus,
  onOpenThread,
  onReact,
  files,
  onOpenMessage,
  onOpenMessageId,
  customTabs,
  canEditCanvas,
}: {
  selected: ChannelTabKey;
  channelId: string;
  currentPubkey?: string;
  tasks: ChannelTasksState | null;
  canSetStatus: boolean;
  onOpenThread: (rootId: string) => void;
  onReact: (eventId: string, emoji: string) => Promise<void>;
  files: ReturnType<typeof useChannelFilesAndLinks>;
  onOpenMessage: (item: FileLinkItem) => void;
  onOpenMessageId: (messageId: string, rootId: string | null) => void;
  customTabs: KnownChannelTab[];
  canEditCanvas: boolean;
}) {
  if (selected.startsWith("custom:")) {
    const tab = customTabs.find((item) => `custom:${item.id}` === selected);
    if (!tab) return null;
    return (
      <CustomTabPanel
        canEditCanvas={canEditCanvas}
        channelId={channelId}
        onOpenMessage={onOpenMessageId}
        onOpenThread={onOpenThread}
        tab={tab}
      />
    );
  }
  if (selected === "files")
    return <ChannelFilesTab files={files} onOpenMessage={onOpenMessage} />;
  if (selected === "pins")
    return (
      <ChannelPinsTab
        channelId={channelId}
        currentPubkey={currentPubkey}
        onOpenMessage={onOpenMessageId}
      />
    );
  if (selected === "tasks" && tasks)
    return (
      <ChannelTasksTab
        canSetStatus={canSetStatus}
        onOpenThread={onOpenThread}
        onReact={onReact}
        tasks={tasks}
      />
    );
  return null;
}
