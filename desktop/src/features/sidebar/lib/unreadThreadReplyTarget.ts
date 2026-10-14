import { getThreadReference } from "@/features/messages/lib/threading";
import type { FeedItem } from "@/shared/api/types";

export type UnreadThreadReplyTarget = {
  itemIds: string[];
  messageId: string;
  threadRootId: string;
};

export function getChannelUnreadThreadFeedItems(
  items: readonly FeedItem[],
  channelId: string,
): FeedItem[] {
  return items.filter((item) => item.channelId === channelId);
}

function threadRootIdOf(item: FeedItem) {
  const thread = getThreadReference(item.tags);
  return thread.rootId ?? thread.parentId;
}

export function getUnreadThreadReplyTarget({
  channelReadAt,
  hasTopLevelUnread,
  items,
}: {
  channelReadAt: number | null;
  hasTopLevelUnread: boolean;
  items: readonly FeedItem[];
}): UnreadThreadReplyTarget | null {
  if (hasTopLevelUnread || channelReadAt === null) return null;
  let oldest: FeedItem | null = null;
  for (const item of items) {
    if (threadRootIdOf(item) && (!oldest || item.createdAt < oldest.createdAt))
      oldest = item;
  }
  const threadRootId = oldest ? threadRootIdOf(oldest) : null;
  if (!oldest || !threadRootId) return null;
  return {
    itemIds: items.flatMap((item) =>
      threadRootIdOf(item) === threadRootId ? [item.id] : [],
    ),
    messageId: oldest.id,
    threadRootId,
  };
}

export function clearThreadUnreadOverrides({
  channelId,
  clearChannelUnreadSource,
  itemIds,
  locallyUnreadFeedItems,
  undoUnread,
}: {
  channelId: string | null;
  clearChannelUnreadSource: (channelId: string, source: "inbox") => void;
  itemIds: Iterable<string>;
  locallyUnreadFeedItems: readonly FeedItem[];
  undoUnread: (itemId: string) => void;
}) {
  const clearedItemIds = new Set(itemIds);
  for (const itemId of clearedItemIds) undoUnread(itemId);
  const hasAnotherChannelOverride = locallyUnreadFeedItems.some(
    (feedItem) =>
      feedItem.channelId === channelId && !clearedItemIds.has(feedItem.id),
  );
  if (channelId && !hasAnotherChannelOverride) {
    clearChannelUnreadSource(channelId, "inbox");
  }
}
