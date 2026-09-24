import { ChevronRight } from "lucide-react";

import { cn } from "@/shared/lib/cn";
import { UserAvatar } from "@/shared/ui/UserAvatar";
import { MessageTimestamp } from "./MessageTimestamp";

/** Single-line plain-text preview; markdown punctuation is noise at this size. */
export function coordinationPreview(body: string): string {
  return body
    .replace(/```[\s\S]*?```/g, " [code] ")
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/[`*_>#~|]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Collapsed placeholder for an `audience=agents` message: one short line that
 * keeps the author's avatar visible. Clicking it expands the full message row.
 */
export function AgentCoordinationCollapsedRow({
  author,
  avatarUrl,
  accent,
  body,
  createdAt,
  isAgent,
  messageId,
  onExpand,
}: {
  author: string;
  avatarUrl?: string | null;
  accent?: boolean;
  body: string;
  createdAt: number;
  isAgent: boolean;
  messageId: string;
  onExpand: () => void;
}) {
  return (
    <button
      type="button"
      aria-expanded={false}
      aria-label={`Agent coordination from ${author}. Show message`}
      className={cn(
        "group/coordination mx-1 flex w-[calc(100%-0.5rem)] min-w-0 items-center gap-2 rounded-md px-2 py-0.5 text-left",
        "text-xs text-muted-foreground/70 hover:bg-muted/50 hover:text-muted-foreground",
        "focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring",
      )}
      data-message-id={messageId}
      data-testid="agent-coordination-collapsed"
      onClick={onExpand}
    >
      {/* Match the 36px avatar gutter so collapsed rows align with full rows. */}
      <span className="flex w-9 shrink-0 justify-center">
        <UserAvatar
          accent={accent}
          avatarUrl={avatarUrl ?? null}
          displayName={author}
          shape={isAgent ? "squircle" : "circle"}
          size="xs"
        />
      </span>
      <span className="shrink-0 font-medium text-muted-foreground">
        {author}
      </span>
      <ChevronRight
        aria-hidden="true"
        className="h-3 w-3 shrink-0 opacity-60 transition-transform group-hover/coordination:translate-x-0.5"
      />
      <span className="min-w-0 flex-1 truncate">
        {coordinationPreview(body)}
      </span>
      <MessageTimestamp
        className="text-muted-foreground/45"
        createdAt={createdAt}
        hideDayPeriod
      />
    </button>
  );
}

/** Header control on an expanded coordination row to fold it back down. */
export function AgentCoordinationCollapseButton({
  onCollapse,
}: {
  onCollapse: () => void;
}) {
  return (
    <button
      type="button"
      aria-expanded={true}
      className="rounded px-1 text-xs text-muted-foreground/70 hover:bg-muted hover:text-muted-foreground focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring"
      data-testid="agent-coordination-collapse"
      onClick={onCollapse}
    >
      Agent coordination · Collapse
    </button>
  );
}
