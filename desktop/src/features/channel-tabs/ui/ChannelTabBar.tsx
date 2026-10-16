import { Plus } from "lucide-react";

import { cn } from "@/shared/lib/cn";
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuTrigger,
} from "@/shared/ui/context-menu";
import type { ChannelTabItem, ChannelTabKey } from "../lib/channelTabItems";
import type { KnownChannelTab } from "../lib/channelTabs";

export function ChannelTabBar({
  items,
  selected,
  onSelect,
  canEdit,
  onAdd,
  onEdit,
  onMove,
  onRemove,
}: {
  items: readonly ChannelTabItem[];
  selected: ChannelTabKey;
  onSelect: (key: ChannelTabKey) => void;
  canEdit: boolean;
  onAdd: () => void;
  onEdit: (tab: KnownChannelTab) => void;
  onMove: (tab: KnownChannelTab, delta: -1 | 1) => void;
  onRemove: (tab: KnownChannelTab) => void;
}) {
  return (
    <div
      aria-label="Channel tabs"
      className="pointer-events-auto flex items-center gap-1 overflow-x-auto px-4 pb-1.5"
      data-testid="channel-tab-bar"
      role="tablist"
    >
      {items.map((item) => {
        const button = (
          <button
            aria-selected={item.key === selected}
            className={cn(
              "shrink-0 rounded-md px-2.5 py-1 text-sm",
              item.key === selected
                ? "bg-muted font-semibold text-foreground"
                : "text-muted-foreground hover:bg-muted/60",
            )}
            data-testid={`channel-tab-${item.key}`}
            key={item.key}
            onClick={() => onSelect(item.key)}
            role="tab"
            type="button"
          >
            {item.label}
            {item.badge ? (
              <span
                className="ml-1.5 rounded-full bg-primary px-1.5 text-xs font-semibold tabular-nums text-primary-foreground"
                data-testid={`channel-tab-badge-${item.key}`}
              >
                {item.badge}
              </span>
            ) : null}
          </button>
        );
        const tab = item.custom;
        if (!tab || !canEdit) return button;
        return (
          <ContextMenu key={item.key}>
            <ContextMenuTrigger asChild>{button}</ContextMenuTrigger>
            <ContextMenuContent>
              <ContextMenuItem onSelect={() => onEdit(tab)}>
                Rename
              </ContextMenuItem>
              <ContextMenuItem onSelect={() => onMove(tab, -1)}>
                Move left
              </ContextMenuItem>
              <ContextMenuItem onSelect={() => onMove(tab, 1)}>
                Move right
              </ContextMenuItem>
              <ContextMenuItem
                className="text-destructive"
                onSelect={() => onRemove(tab)}
              >
                Delete
              </ContextMenuItem>
            </ContextMenuContent>
          </ContextMenu>
        );
      })}
      {canEdit ? (
        <button
          aria-label="Add tab"
          className="shrink-0 rounded-md p-1 text-muted-foreground hover:bg-muted/60"
          data-testid="channel-tab-add"
          onClick={onAdd}
          type="button"
        >
          <Plus className="h-4 w-4" />
        </button>
      ) : null}
    </div>
  );
}
