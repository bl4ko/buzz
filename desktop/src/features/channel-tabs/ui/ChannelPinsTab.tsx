import * as React from "react";
import { toast } from "sonner";

import type { PinnedMessage } from "@/features/messages/lib/messagePins";
import { getThreadReference } from "@/features/messages/lib/threading";
import { useChannelPinsContext } from "@/features/messages/ui/ChannelPinsContext";
import { useUsersBatchQuery } from "@/features/profile/hooks";
import { authorPubkeyOf, ChannelPinsList } from "./ChannelPinsList";

export function ChannelPinsTab({
  channelId,
  currentPubkey,
  onOpenMessage,
}: {
  channelId: string;
  currentPubkey?: string;
  onOpenMessage: (messageId: string, rootId: string | null) => void;
}) {
  const pins = useChannelPinsContext(channelId);
  const pinnedMessages = pins?.pinnedMessages ?? [];
  const authorPubkeys = React.useMemo(
    () => pinnedMessages.map(authorPubkeyOf),
    [pinnedMessages],
  );
  const profiles = useUsersBatchQuery(authorPubkeys).data?.profiles;

  if (!pins) return null;

  const unpin = (item: PinnedMessage) => {
    void pins.setPinned(item.target.id, false).then(
      () => toast.success("Message unpinned"),
      (error) => {
        console.error("Failed to unpin message", error);
        toast.error("Couldn't unpin message");
      },
    );
  };

  return (
    <ChannelPinsList
      canPin={pins.canPin}
      currentPubkey={currentPubkey}
      isLoading={pins.isLoading}
      onOpenMessage={(item) =>
        onOpenMessage(
          item.target.id,
          getThreadReference(item.target.tags).rootId ?? null,
        )
      }
      onUnpin={unpin}
      pinnedMessages={pinnedMessages}
      profiles={profiles}
    />
  );
}
