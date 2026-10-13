import * as React from "react";
import { toast } from "sonner";

import { isPinnableMessage } from "@/features/messages/lib/messagePins";
import type { TimelineMessage } from "@/features/messages/types";
import type { ChannelPinsState } from "@/features/messages/useChannelPins";

export type ChannelPinsContextValue = ChannelPinsState & {
  canPin: boolean;
};

const ChannelPinsContext = React.createContext<ChannelPinsContextValue | null>(
  null,
);

export function ChannelPinsProvider({
  canPin,
  children,
  pins,
}: {
  canPin: boolean;
  children: React.ReactNode;
  pins: ChannelPinsState | null;
}) {
  const value = React.useMemo(
    () => (pins ? { ...pins, canPin } : null),
    [canPin, pins],
  );
  return (
    <ChannelPinsContext.Provider value={value}>
      {children}
    </ChannelPinsContext.Provider>
  );
}

export function useChannelPinsContext(channelId: string | null | undefined) {
  const value = React.useContext(ChannelPinsContext);
  return value && channelId && value.channelId === channelId ? value : null;
}

export function useMessagePinToggle(
  channelId: string | null | undefined,
  message: TimelineMessage,
) {
  const pins = useChannelPinsContext(channelId);
  if (!pins?.canPin || !isPinnableMessage(message)) {
    return null;
  }
  const pinned = pins.isPinned(message.id);
  return {
    pinned,
    toggle: () => {
      void pins.setPinned(message.id, !pinned).then(
        () => toast.success(pinned ? "Message unpinned" : "Message pinned"),
        (error) => {
          console.error("Failed to update pinned message", error);
          toast.error(
            pinned ? "Couldn't unpin message" : "Couldn't pin message",
          );
        },
      );
    },
  };
}
