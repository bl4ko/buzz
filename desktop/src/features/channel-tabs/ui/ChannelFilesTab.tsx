import * as React from "react";

import { rewriteRelayUrl } from "@/shared/lib/mediaUrl";
import { cn } from "@/shared/lib/cn";
import { Button } from "@/shared/ui/button";
import {
  type FileLinkFilter,
  type FileLinkItem,
  filterFilesAndLinks,
} from "../lib/filesAndLinks";

const FILTERS: { value: FileLinkFilter; label: string }[] = [
  { value: "all", label: "All" },
  { value: "files", label: "Files" },
  { value: "media", label: "Media" },
  { value: "links", label: "Links" },
];
const GRID_PREVIEW = 8;

export function ChannelFilesTab({
  files,
  onOpenMessage,
}: {
  files: {
    items: FileLinkItem[];
    isLoading: boolean;
    hasMore: boolean;
    loadMore: () => unknown;
  };
  onOpenMessage: (item: FileLinkItem) => void;
}) {
  const [filter, setFilter] = React.useState<FileLinkFilter>("all");
  const [query, setQuery] = React.useState("");
  const shown = filterFilesAndLinks(files.items, filter, query);
  const media = shown.filter((item) => item.kind === "media");
  const rows = shown.filter((item) => item.kind !== "media");
  const grid = filter === "media" ? media : media.slice(0, GRID_PREVIEW);
  return (
    <div
      className="mx-auto max-w-3xl space-y-4 py-4"
      data-testid="channel-files-tab"
    >
      <input
        aria-label="Search files and links"
        className="w-full rounded-md border border-border bg-background px-3 py-1.5 text-sm"
        data-testid="files-search"
        onChange={(event) => setQuery(event.target.value)}
        placeholder="Search files and links"
        type="search"
        value={query}
      />
      <fieldset aria-label="Filter" className="m-0 flex gap-1 border-0 p-0">
        {FILTERS.map((option) => (
          <button
            aria-pressed={filter === option.value}
            className={cn(
              "rounded-md px-2.5 py-1 text-sm",
              filter === option.value
                ? "bg-muted font-semibold"
                : "text-muted-foreground hover:bg-muted/60",
            )}
            data-testid={`files-filter-${option.value}`}
            key={option.value}
            onClick={() => setFilter(option.value)}
            type="button"
          >
            {option.label}
          </button>
        ))}
      </fieldset>
      {grid.length > 0 ? (
        <section className="space-y-2" data-testid="files-media">
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-semibold">Photos and videos</h3>
            {filter !== "media" && media.length > GRID_PREVIEW ? (
              <button
                className="text-sm text-primary"
                data-testid="files-see-all"
                onClick={() => setFilter("media")}
                type="button"
              >
                See all
              </button>
            ) : null}
          </div>
          <div className="grid grid-cols-4 gap-2">
            {grid.map((item) => (
              <button
                data-testid="files-media-item"
                key={item.key}
                onClick={() => onOpenMessage(item)}
                type="button"
              >
                <img
                  alt={item.name}
                  className="aspect-square w-full rounded-md object-cover"
                  loading="lazy"
                  src={rewriteRelayUrl(item.thumb ?? item.url)}
                />
              </button>
            ))}
          </div>
        </section>
      ) : null}
      {filter !== "media" && rows.length > 0 ? (
        <ul className="divide-y divide-border/60">
          {rows.map((item) => (
            <li key={item.key}>
              <button
                className="flex w-full flex-col items-start px-2 py-2 text-left hover:bg-muted/60"
                data-kind={item.kind}
                data-testid="files-row"
                onClick={() => onOpenMessage(item)}
                type="button"
              >
                <span className="truncate text-sm font-medium">
                  {item.kind === "link" ? item.host : item.name}
                </span>
                <span className="truncate text-xs text-muted-foreground">
                  {item.kind === "link" ? item.path : item.host}
                </span>
              </button>
            </li>
          ))}
        </ul>
      ) : null}
      {shown.length === 0 && !files.isLoading ? (
        <p className="py-6 text-center text-sm text-muted-foreground">
          No files or links found.
        </p>
      ) : null}
      {files.hasMore ? (
        <Button
          onClick={() => void files.loadMore()}
          size="sm"
          type="button"
          variant="outline"
        >
          Load older
        </Button>
      ) : null}
    </div>
  );
}
