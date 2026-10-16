import type { ChannelTabKey } from "../lib/channelTabItems";
import type { ChannelTasksState } from "../useChannelTasks";
import type { FileLinkItem } from "../lib/filesAndLinks";
import type { useChannelFilesAndLinks } from "../useChannelFilesAndLinks";
import { ChannelFilesTab } from "./ChannelFilesTab";
import { ChannelPinsTab } from "./ChannelPinsTab";
import { ChannelTasksTab } from "./ChannelTasksTab";

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
}) {
  if (selected === "files")
    return <ChannelFilesTab files={files} onOpenMessage={onOpenMessage} />;
  if (selected === "pins")
    return (
      <ChannelPinsTab channelId={channelId} currentPubkey={currentPubkey} />
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
