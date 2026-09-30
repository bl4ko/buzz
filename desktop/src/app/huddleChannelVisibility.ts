import type { Channel } from "@/shared/api/types";

export function shouldShowSidebarChannel(channel: Channel): boolean {
  return channel.archivedAt === null;
}
