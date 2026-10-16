import { useQuery } from "@tanstack/react-query";
import { openUrl } from "@tauri-apps/plugin-opener";

import { getThreadReference } from "@/features/messages/lib/threading";
import { useChannelMembersQuery } from "@/features/channels/hooks";
import { useSearchMessagesQuery } from "@/features/search/hooks";
import { relayClient } from "@/shared/api/relayClient";
import { Button } from "@/shared/ui/button";
import { Markdown } from "@/shared/ui/markdown";
import { type KnownChannelTab, validateTabValue } from "../lib/channelTabs";
import { ChannelCanvasDocTab } from "./ChannelCanvasDocTab";
import { authorOnlyFilter, resolveSearchTab } from "../lib/searchTab";

function LinkTab({ url }: { url: string }) {
  return (
    <div className="flex h-full flex-col gap-2" data-testid="custom-tab-link">
      <div className="flex items-center justify-between gap-2 text-sm">
        <span className="truncate text-muted-foreground">{url}</span>
        <Button
          data-testid="custom-tab-open-browser"
          onClick={() => void openUrl(url)}
          size="sm"
          type="button"
          variant="outline"
        >
          Open in browser
        </Button>
      </div>
      <iframe
        className="min-h-[70vh] w-full flex-1 rounded-md border border-border"
        referrerPolicy="no-referrer"
        sandbox="allow-scripts allow-same-origin allow-forms allow-popups"
        src={url}
        title={url}
      />
    </div>
  );
}

function SearchTab({
  channelId,
  value,
  onOpenMessage,
}: {
  channelId: string;
  value: string;
  onOpenMessage: (messageId: string, rootId: string | null) => void;
}) {
  const members = useChannelMembersQuery(channelId, true).data ?? [];
  const search = resolveSearchTab(value, members);
  const results = useSearchMessagesQuery(search.text, {
    channelId,
    authors: search.authors,
    since: search.since,
    until: search.until,
    limit: 50,
    minimumQueryLength: 1,
    enabled: search.unresolved === null,
  });
  const authorFilter = authorOnlyFilter(search, channelId);
  const authorEvents = useQuery({
    enabled: authorFilter !== null,
    queryKey: ["custom-tab-author-search", JSON.stringify(authorFilter)],
    queryFn: async () => {
      const events = await relayClient.fetchEvents(
        authorFilter as NonNullable<typeof authorFilter>,
      );
      return [...events].sort((a, b) => b.created_at - a.created_at);
    },
  });
  if (search.unresolved)
    return (
      <p className="py-6 text-sm text-muted-foreground">
        No channel member named {search.unresolved}.
      </p>
    );
  const hits = authorFilter
    ? (authorEvents.data ?? []).map((event) => ({
        eventId: event.id,
        content: event.content,
        threadRootId: getThreadReference(event.tags).rootId ?? null,
      }))
    : (results.data?.hits ?? []);
  const loading = authorFilter ? authorEvents.isLoading : results.isLoading;
  return (
    <ul className="divide-y divide-border/60" data-testid="custom-tab-search">
      {hits.map((hit) => (
        <li key={hit.eventId}>
          <button
            className="w-full px-2 py-2 text-left hover:bg-muted/60"
            onClick={() => onOpenMessage(hit.eventId, hit.threadRootId ?? null)}
            type="button"
          >
            <Markdown content={hit.content} />
          </button>
        </li>
      ))}
      {hits.length === 0 && !loading ? (
        <li className="py-6 text-sm text-muted-foreground">
          No messages match.
        </li>
      ) : null}
    </ul>
  );
}

function ThreadTab({
  channelId,
  rootId,
  onOpenThread,
}: {
  channelId: string;
  rootId: string;
  onOpenThread: (rootId: string) => void;
}) {
  const thread = useQuery({
    queryKey: ["custom-tab-thread", channelId, rootId],
    queryFn: async () => {
      const [root, replies] = await Promise.all([
        relayClient.fetchEvents({
          ids: [rootId],
          kinds: [9, 40002, 45001],
          limit: 1,
        }),
        relayClient.fetchEvents({
          kinds: [9, 40002],
          "#h": [channelId],
          "#e": [rootId],
          limit: 200,
        }),
      ]);
      return [...root, ...replies].sort((a, b) => a.created_at - b.created_at);
    },
  });
  return (
    <div className="space-y-3" data-testid="custom-tab-thread">
      <Button
        onClick={() => onOpenThread(rootId)}
        size="sm"
        type="button"
        variant="outline"
      >
        Open thread
      </Button>
      {(thread.data ?? []).map((event) => (
        <div
          className="rounded-md border border-border/60 px-3 py-2"
          key={event.id}
        >
          <Markdown content={event.content} />
        </div>
      ))}
    </div>
  );
}

export function CustomTabPanel({
  tab,
  channelId,
  canEditCanvas,
  onOpenMessage,
  onOpenThread,
}: {
  tab: KnownChannelTab;
  channelId: string;
  canEditCanvas: boolean;
  onOpenMessage: (messageId: string, rootId: string | null) => void;
  onOpenThread: (rootId: string) => void;
}) {
  if (validateTabValue(tab.type, tab.value) !== null) {
    return (
      <p
        className="py-6 text-sm text-destructive"
        data-testid="custom-tab-invalid"
      >
        This tab has an invalid value.
      </p>
    );
  }
  if (tab.type === "link") return <LinkTab url={tab.value.trim()} />;
  if (tab.type === "search")
    return (
      <SearchTab
        channelId={channelId}
        onOpenMessage={onOpenMessage}
        value={tab.value}
      />
    );
  if (tab.type === "thread")
    return (
      <ThreadTab
        channelId={channelId}
        onOpenThread={onOpenThread}
        rootId={tab.value}
      />
    );
  if (tab.type === "canvas")
    return (
      <ChannelCanvasDocTab
        canEdit={canEditCanvas}
        canvasId={tab.value}
        channelId={channelId}
      />
    );
  return null;
}
