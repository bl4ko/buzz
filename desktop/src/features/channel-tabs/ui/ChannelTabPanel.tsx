import type { ChannelTabKey } from "../lib/channelTabItems";
import type { ChannelTasksState } from "../useChannelTasks";
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
}: {
  selected: ChannelTabKey;
  channelId: string;
  currentPubkey?: string;
  tasks: ChannelTasksState | null;
  canSetStatus: boolean;
  onOpenThread: (rootId: string) => void;
  onReact: (eventId: string, emoji: string) => Promise<void>;
}) {
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
