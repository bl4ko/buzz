import type { Channel } from "@/shared/api/types";

export function isHuddleBackingChannel(
  channel: Channel,
  huddleBackingChannelIds: ReadonlySet<string>,
): boolean {
  return (
    huddleBackingChannelIds.has(channel.id) ||
    (/^huddle-[0-9a-f]{8}$/.test(channel.name) &&
      channel.channelType === "stream" &&
      channel.visibility === "private" &&
      channel.ttlSeconds === 3_600)
  );
}

export function shouldShowSidebarChannel(
  channel: Channel,
  huddleBackingChannelIds: ReadonlySet<string>,
): boolean {
  return !isHuddleBackingChannel(channel, huddleBackingChannelIds);
}
