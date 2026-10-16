import * as React from "react";

import { useAppNavigation } from "@/app/navigation/useAppNavigation";
import { useToggleReactionMutation } from "@/features/messages/hooks";

import type { FileLinkItem } from "./lib/filesAndLinks";
import {
  buildChannelTabItems,
  type ChannelTabKey,
  resolveSelectedTab,
} from "./lib/channelTabItems";
import { ChannelTabBar } from "./ui/ChannelTabBar";
import { ChannelTabPanel } from "./ui/ChannelTabPanel";
import { useChannelFilesAndLinks } from "./useChannelFilesAndLinks";
import { useChannelTabs } from "./useChannelTabs";
import { useChannelTasks } from "./useChannelTasks";
import { useTaskPermissions } from "./useTaskPermissions";

export function useChannelTabsModel({
  channelId,
  currentPubkey,
  pinCount,
}: {
  channelId: string | null;
  currentPubkey?: string;
  pinCount: number;
}) {
  const [selection, setSelection] = React.useState<{
    channelId: string | null;
    key: ChannelTabKey;
  }>({ channelId, key: "messages" });
  const selected =
    selection.channelId === channelId ? selection.key : "messages";
  const setSelected = React.useCallback(
    (key: ChannelTabKey) => setSelection({ channelId, key }),
    [channelId],
  );
  const permissions = useTaskPermissions(channelId, currentPubkey);
  const tasks = useChannelTasks(channelId);
  const tabs = useChannelTabs(channelId, permissions.canEditTabsFor);
  const files = useChannelFilesAndLinks(channelId);
  const items = React.useMemo(
    () =>
      buildChannelTabItems({
        taskCount: tasks?.tasks.length ?? 0,
        awaitingCount: tasks?.awaitingCount ?? 0,
        pinCount,
        fileCount: files.items.length,
        customTabs: tabs?.visible ?? [],
      }),
    [tasks, pinCount, files.items.length, tabs?.visible],
  );
  const { goChannel } = useAppNavigation();
  const reaction = useToggleReactionMutation();
  const onOpenThread = React.useCallback(
    (rootId: string) => {
      if (!channelId) return;
      setSelected("messages");
      void goChannel(channelId, { thread: rootId });
    },
    [channelId, goChannel, setSelected],
  );
  const onOpenMessage = React.useCallback(
    (item: FileLinkItem) => {
      if (!channelId) return;
      setSelected("messages");
      void goChannel(channelId, {
        messageId: item.messageId,
        threadRootId: item.rootId ?? undefined,
      });
    },
    [channelId, goChannel, setSelected],
  );
  const onReact = React.useCallback(
    async (eventId: string, emoji: string) => {
      await reaction.mutateAsync({ eventId, emoji, remove: false });
    },
    [reaction],
  );
  const current = resolveSelectedTab(items, selected);
  if (!channelId) return { tabBar: null, tabPanel: null };
  const tabBar = (
    <ChannelTabBar
      canEdit={permissions.canEditTabs}
      items={items}
      onAdd={() => {}}
      onEdit={() => {}}
      onMove={() => {}}
      onRemove={() => {}}
      onSelect={setSelected}
      selected={current}
    />
  );
  const tabPanel =
    current === "messages" ? null : (
      <ChannelTabPanel
        canSetStatus={permissions.canSetStatus}
        channelId={channelId}
        currentPubkey={currentPubkey}
        onOpenThread={onOpenThread}
        files={files}
        onOpenMessage={onOpenMessage}
        onReact={onReact}
        selected={current}
        tasks={tasks}
      />
    );
  return { tabBar, tabPanel };
}
