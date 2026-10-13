import { Pin } from "lucide-react";

import {
  resolveUserLabel,
  type UserProfileLookup,
} from "@/features/profile/lib/identity";
import { useChannelPinsContext } from "./ChannelPinsContext";

export function MessagePinnedLine({
  channelId,
  currentPubkey,
  messageId,
  profiles,
}: {
  channelId?: string | null;
  currentPubkey?: string;
  messageId: string;
  profiles?: UserProfileLookup;
}) {
  const pins = useChannelPinsContext(channelId);
  const pin = pins?.isPinned(messageId) ? pins.pins.get(messageId) : undefined;
  if (!pin) return null;
  const pinnedBy = resolveUserLabel({
    currentPubkey,
    profiles,
    pubkey: pin.pubkey,
  });

  return (
    <div
      className="mb-0.5 flex items-center gap-1 text-xs font-medium text-amber-600 dark:text-amber-400"
      data-testid="message-pinned-indicator"
    >
      <Pin aria-hidden="true" className="h-3 w-3" />
      <span>Pinned</span>
      <span className="truncate font-normal text-muted-foreground">
        by {pinnedBy}
      </span>
    </div>
  );
}
