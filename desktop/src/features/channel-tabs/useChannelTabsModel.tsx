import * as React from "react";
import { toast } from "sonner";

import { useAppNavigation } from "@/app/navigation/useAppNavigation";
import { useToggleReactionMutation } from "@/features/messages/hooks";

import type { FileLinkItem } from "./lib/filesAndLinks";
import {
  buildChannelTabItems,
  type ChannelTabKey,
  resolveSelectedTab,
} from "./lib/channelTabItems";
import {
  addTab,
  type ChannelTab,
  moveTab,
  removeTab,
  renameTab,
} from "./lib/channelTabs";
import { AddChannelTabDialog } from "./ui/AddChannelTabDialog";
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
  const tasks = useChannelTasks(channelId, undefined, currentPubkey);
  const tabs = useChannelTabs(channelId);
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
  const onOpenMessageId = React.useCallback(
    (messageId: string, rootId: string | null) => {
      if (!channelId) return;
      setSelected("messages");
      void goChannel(channelId, {
        messageId,
        threadRootId: rootId ?? undefined,
      });
    },
    [channelId, goChannel, setSelected],
  );
  const onOpenMessage = React.useCallback(
    (item: FileLinkItem) => onOpenMessageId(item.messageId, item.rootId),
    [onOpenMessageId],
  );
  const onReact = React.useCallback(
    async (eventId: string, emoji: string) => {
      await reaction.mutateAsync({ eventId, emoji, remove: false });
    },
    [reaction],
  );
  const [dialog, setDialog] = React.useState<{
    open: boolean;
    initial: ChannelTab | null;
  }>({ open: false, initial: null });
  const saveTabs = React.useCallback(
    async (next: ChannelTab[]) => {
      try {
        await tabs?.save(next);
        return true;
      } catch (error) {
        console.error("Failed to save channel tabs", error);
        toast.error("Couldn't save the tabs");
        return false;
      }
    },
    [tabs],
  );
  const current = resolveSelectedTab(items, selected);
  if (!channelId) return { tabBar: null, tabPanel: null };
  const allTabs = tabs?.tabs ?? [];
  const tabBar = (
    <>
      <ChannelTabBar
        canEdit={permissions.canEditTabs}
        items={items}
        onAdd={() => setDialog({ open: true, initial: null })}
        onEdit={(tab) => setDialog({ open: true, initial: tab })}
        onMove={(tab, delta) => void saveTabs(moveTab(allTabs, tab.id, delta))}
        onRemove={(tab) => void saveTabs(removeTab(allTabs, tab.id))}
        onSelect={setSelected}
        selected={current}
      />
      <AddChannelTabDialog
        initial={dialog.initial}
        onOpenChange={(open) => setDialog((state) => ({ ...state, open }))}
        onSubmit={async (tab) => {
          const saved = await saveTabs(
            dialog.initial
              ? renameTab(allTabs, tab.id, tab.title)
              : addTab(allTabs, tab),
          );
          if (!saved) throw new Error("Tab save failed");
          setDialog({ open: false, initial: null });
        }}
        open={dialog.open}
      />
    </>
  );
  const tabPanel =
    current === "messages" ? null : (
      <ChannelTabPanel
        canSetStatus={permissions.canSetStatus}
        channelId={channelId}
        canEditCanvas={permissions.canEditCanvas}
        currentPubkey={currentPubkey}
        customTabs={tabs?.visible ?? []}
        onOpenThread={onOpenThread}
        files={files}
        onOpenMessage={onOpenMessage}
        onOpenMessageId={onOpenMessageId}
        onReact={onReact}
        selected={current}
        tasks={tasks}
      />
    );
  return { tabBar, tabPanel };
}
