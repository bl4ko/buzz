import * as React from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";

import { getChannelTasks } from "@/shared/api/channelTasks";
import type { RelayEvent } from "@/shared/api/types";
import { KIND_THREAD_STATUS } from "@/shared/constants/kinds";
import {
  type ChannelEventTransport,
  mergeEvent,
  relayChannelEventTransport,
  useLiveChannelEvents,
} from "./channelEventTransport";
import {
  buildThreadStatusTags,
  groupThreadTasks,
  reduceThreadTasks,
  type TaskGroups,
  type TaskStatus,
  type ThreadTask,
} from "./lib/threadStatus";

export type ChannelTasksTransport = ChannelEventTransport & {
  fetchTasks: (channelId: string) => Promise<RelayEvent[]>;
};

export const relayChannelTasksTransport: ChannelTasksTransport = {
  ...relayChannelEventTransport("task"),
  fetchTasks: getChannelTasks,
};

export function channelTasksKey(channelId: string) {
  return ["channel-tasks", channelId] as const;
}

export type ChannelTasksState = {
  channelId: string;
  tasks: ThreadTask[];
  groups: TaskGroups;
  awaitingCount: number;
  isLoading: boolean;
  setStatus: (task: ThreadTask, status: TaskStatus) => Promise<void>;
};

export function useChannelTasks(
  channelId: string | null,
  transport: ChannelTasksTransport = relayChannelTasksTransport,
): ChannelTasksState | null {
  const queryClient = useQueryClient();
  const key = channelTasksKey(channelId ?? "none");
  const query = useQuery({
    enabled: channelId !== null,
    queryKey: key,
    queryFn: () => transport.fetchTasks(channelId ?? ""),
    staleTime: Number.POSITIVE_INFINITY,
  });
  useLiveChannelEvents(
    channelId,
    channelId ? { kinds: [KIND_THREAD_STATUS], "#h": [channelId] } : null,
    key,
    transport,
  );
  const taskMap = React.useMemo(
    () => reduceThreadTasks(query.data ?? [], channelId ?? ""),
    [query.data, channelId],
  );
  const setStatus = React.useCallback(
    async (task: ThreadTask, status: TaskStatus) => {
      if (!channelId) return;
      const signed = await transport.signEvent({
        kind: KIND_THREAD_STATUS,
        content: "",
        createdAt: Math.max(transport.now(), task.createdAt + 1),
        tags: buildThreadStatusTags({
          rootId: task.rootId,
          channelId,
          status,
          title: task.title,
          ask: null,
        }),
      });
      await transport.publishEvent(signed);
      queryClient.setQueryData<RelayEvent[]>(
        channelTasksKey(channelId),
        (current = []) => mergeEvent(current, signed),
      );
    },
    [channelId, queryClient, transport],
  );
  return React.useMemo(() => {
    if (!channelId) return null;
    const tasks = [...taskMap.values()];
    const groups = groupThreadTasks(tasks);
    return {
      channelId,
      tasks,
      groups,
      awaitingCount: groups.needsYou.length,
      isLoading: query.isLoading,
      setStatus,
    };
  }, [channelId, taskMap, query.isLoading, setStatus]);
}
