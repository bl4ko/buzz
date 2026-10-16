import * as React from "react";
import { useInfiniteQuery } from "@tanstack/react-query";

import { getChannelFilesAndLinks } from "@/shared/api/channelTasks";
import type { RelayEvent } from "@/shared/api/types";
import { extractFilesAndLinks } from "./lib/filesAndLinks";

const PAGE = 100;

export function useChannelFilesAndLinks(
  channelId: string | null,
  fetchPage: (
    channelId: string,
    until?: number,
  ) => Promise<RelayEvent[]> = getChannelFilesAndLinks,
) {
  const query = useInfiniteQuery({
    enabled: channelId !== null,
    queryKey: ["channel-files", channelId ?? "none"],
    initialPageParam: undefined as number | undefined,
    queryFn: ({ pageParam }) => fetchPage(channelId ?? "", pageParam),
    getNextPageParam: (last) =>
      last.length >= PAGE
        ? Math.min(...last.map((event) => event.created_at))
        : undefined,
    staleTime: 60_000,
  });
  const items = React.useMemo(
    () => extractFilesAndLinks(query.data?.pages.flat() ?? []),
    [query.data],
  );
  return {
    items,
    isLoading: query.isLoading,
    hasMore: query.hasNextPage,
    loadMore: () => query.fetchNextPage(),
  };
}
