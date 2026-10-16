import { invokeTauri } from "@/shared/api/tauri";
import type { RelayEvent } from "@/shared/api/types";

export async function getChannelTasks(
  channelId: string,
): Promise<RelayEvent[]> {
  return invokeTauri<RelayEvent[]>("get_channel_tasks", { channelId });
}

export async function getChannelFilesAndLinks(
  channelId: string,
  until?: number,
): Promise<RelayEvent[]> {
  return invokeTauri<RelayEvent[]>("get_channel_files_and_links", {
    channelId,
    until: until ?? null,
  });
}
