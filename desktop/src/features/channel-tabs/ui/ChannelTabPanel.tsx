import type { ChannelTabKey } from "../lib/channelTabItems";
import { ChannelPinsTab } from "./ChannelPinsTab";

export function ChannelTabPanel({
  selected,
  channelId,
  currentPubkey,
}: {
  selected: ChannelTabKey;
  channelId: string;
  currentPubkey?: string;
}) {
  if (selected === "pins")
    return (
      <ChannelPinsTab channelId={channelId} currentPubkey={currentPubkey} />
    );
  return null;
}
