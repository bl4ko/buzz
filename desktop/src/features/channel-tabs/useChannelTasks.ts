import * as React from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";

import { getChannelTasks } from "@/shared/api/channelTasks";
import type { RelayEvent } from "@/shared/api/types";
import { KIND_REACTION, KIND_THREAD_STATUS } from "@/shared/constants/kinds";
import {
  type ChannelEventTransport,
  mergeEvent,
  relayChannelEventTransport,
  useLiveChannelEvents,
} from "./channelEventTransport";
import {
  buildThreadStatusTags,
  groupThreadTasks,
  type OwnerDecision,
  ownerDecisions,
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
  decisions: ReadonlyMap<string, OwnerDecision>;
  refreshDecisions: () => void;
  setStatus: (task: ThreadTask, status: TaskStatus) => Promise<void>;
};

export function useChannelTasks(
  channelId: string | null,
  transport: ChannelTasksTransport = relayChannelTasksTransport,
  currentPubkey?: string,
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
  const me = currentPubkey?.toLowerCase() ?? "";
  const askIds = React.useMemo(
    () =>
      [...taskMap.values()]
        .flatMap((task) => (task.ask ? [task.ask.eventId] : []))
        .sort(),
    [taskMap],
  );
  const decisionFilter =
    channelId && me && askIds.length > 0
      ? {
          kinds: [KIND_REACTION],
          authors: [me],
          "#e": askIds,
          "#h": [channelId],
        }
      : null;
  const decisionKey = [
    "channel-task-decisions",
    channelId ?? "none",
    me,
    askIds.join(","),
  ] as const;
  const decisionQuery = useQuery({
    enabled: decisionFilter !== null,
    queryKey: decisionKey,
    queryFn: () =>
      decisionFilter
        ? transport.fetchEvents({ ...decisionFilter, limit: 500 })
        : Promise.resolve([]),
  });
  useLiveChannelEvents(channelId, decisionFilter, decisionKey, transport);
  const decisions = React.useMemo(
    () => ownerDecisions(decisionQuery.data ?? [], me),
    [decisionQuery.data, me],
  );
  const decisionKeyString = JSON.stringify(decisionKey);
  const refreshDecisions = React.useCallback(() => {
    void queryClient.invalidateQueries({
      queryKey: JSON.parse(decisionKeyString) as unknown[],
    });
  }, [decisionKeyString, queryClient]);
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
      awaitingCount: groups.needsYou.filter(
        (task) => !task.ask || !decisions.has(task.ask.eventId),
      ).length,
      isLoading: query.isLoading,
      decisions,
      refreshDecisions,
      setStatus,
    };
  }, [
    channelId,
    taskMap,
    query.isLoading,
    decisions,
    refreshDecisions,
    setStatus,
  ]);
}
