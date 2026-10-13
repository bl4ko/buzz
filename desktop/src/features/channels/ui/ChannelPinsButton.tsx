import { Pin, PinOff } from "lucide-react";
import * as React from "react";
import { toast } from "sonner";

import { useAppNavigation } from "@/app/navigation/useAppNavigation";
import { formatFullDateTime } from "@/features/messages/lib/dateFormatters";
import type { PinnedMessage } from "@/features/messages/lib/messagePins";
import { getThreadReference } from "@/features/messages/lib/threading";
import { useChannelPinsContext } from "@/features/messages/ui/ChannelPinsContext";
import { useUsersBatchQuery } from "@/features/profile/hooks";
import { resolveUserLabel } from "@/features/profile/lib/identity";
import { resolveEventAuthorPubkey } from "@/shared/lib/authors";
import { normalizePubkey } from "@/shared/lib/pubkey";
import { Button } from "@/shared/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@/shared/ui/popover";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/shared/ui/tooltip";
import { UserAvatar } from "@/shared/ui/UserAvatar";

function authorPubkeyOf(item: PinnedMessage) {
  return normalizePubkey(
    resolveEventAuthorPubkey({
      event: item.target,
      preferActorTag: true,
      requireChannelTagForPTags: true,
    }),
  );
}

function previewText(content: string) {
  const text = content.replace(/\s+/g, " ").trim();
  return text.length > 0 ? text : "Attachment";
}

export function ChannelPinsButton({
  channelId,
  currentPubkey,
}: {
  channelId: string | null | undefined;
  currentPubkey?: string;
}) {
  const pins = useChannelPinsContext(channelId);
  const [open, setOpen] = React.useState(false);
  const { goChannel } = useAppNavigation();
  const pinnedMessages = pins?.pinnedMessages ?? [];
  const authorPubkeys = React.useMemo(
    () => pinnedMessages.map(authorPubkeyOf),
    [pinnedMessages],
  );
  const profiles = useUsersBatchQuery(authorPubkeys, { enabled: open }).data
    ?.profiles;

  if (!pins || !channelId) return null;
  const count = pinnedMessages.length;

  const openMessage = (item: PinnedMessage) => {
    setOpen(false);
    void goChannel(channelId, {
      messageId: item.target.id,
      threadRootId: getThreadReference(item.target.tags).rootId,
    });
  };

  const unpin = (item: PinnedMessage) => {
    void pins.setPinned(item.target.id, false).then(
      () => toast.success("Message unpinned"),
      (error) => {
        console.error("Failed to unpin message", error);
        toast.error("Couldn't unpin message");
      },
    );
  };

  return (
    <Popover onOpenChange={setOpen} open={open}>
      <Tooltip disableHoverableContent>
        <TooltipTrigger asChild>
          <PopoverTrigger asChild>
            <Button
              aria-label={`Pinned messages (${count})`}
              className="h-8 px-2.5"
              data-testid="channel-pins-trigger"
              type="button"
              variant={open ? "secondary" : "outline"}
            >
              <Pin />
              {count > 0 ? (
                <span className="min-w-[1ch] text-sm font-medium tabular-nums">
                  {count}
                </span>
              ) : null}
            </Button>
          </PopoverTrigger>
        </TooltipTrigger>
        <TooltipContent>Pinned messages</TooltipContent>
      </Tooltip>
      <PopoverContent
        align="end"
        className="w-96 p-0"
        data-testid="channel-pins-panel"
      >
        <div className="border-b border-border/70 px-4 py-3 text-sm font-semibold">
          Pinned messages
        </div>
        {count === 0 ? (
          <p className="px-4 py-6 text-center text-sm text-muted-foreground">
            {pins.isLoading
              ? "Loading pinned messages…"
              : "No pinned messages yet."}
          </p>
        ) : (
          <ul className="max-h-96 overflow-y-auto py-1">
            {pinnedMessages.map((item) => {
              const authorPubkey = authorPubkeyOf(item);
              const profile = profiles?.[authorPubkey];
              const authorLabel = resolveUserLabel({
                currentPubkey,
                profiles,
                pubkey: authorPubkey,
              });
              return (
                <li
                  className="group/pin flex items-start gap-2 px-2"
                  data-testid="channel-pin-row"
                  key={item.target.id}
                >
                  <button
                    className="flex min-w-0 flex-1 items-start gap-2.5 rounded-lg px-2 py-2 text-left hover:bg-muted/60 focus-visible:outline-hidden focus-visible:ring-1 focus-visible:ring-ring"
                    onClick={() => openMessage(item)}
                    type="button"
                  >
                    <UserAvatar
                      accent={profile?.isAgent === true}
                      avatarUrl={profile?.avatarUrl ?? null}
                      className="h-7 w-7 shrink-0 text-xs"
                      displayName={authorLabel}
                      shape={profile?.isAgent ? "squircle" : "circle"}
                      size="sm"
                    />
                    <span className="flex min-w-0 flex-1 flex-col">
                      <span className="flex items-baseline gap-2">
                        <span className="truncate text-sm font-semibold">
                          {authorLabel}
                        </span>
                        <span className="shrink-0 text-xs text-muted-foreground">
                          {formatFullDateTime(item.target.created_at)}
                        </span>
                      </span>
                      <span className="line-clamp-2 break-words text-sm text-muted-foreground">
                        {previewText(item.target.content)}
                      </span>
                    </span>
                  </button>
                  {pins.canPin ? (
                    <Button
                      aria-label="Unpin message"
                      className="mt-2 h-7 w-7 shrink-0 p-0"
                      data-testid={`unpin-message-${item.target.id}`}
                      onClick={() => unpin(item)}
                      size="sm"
                      title="Unpin"
                      type="button"
                      variant="ghost"
                    >
                      <PinOff className="h-4 w-4" />
                    </Button>
                  ) : null}
                </li>
              );
            })}
          </ul>
        )}
      </PopoverContent>
    </Popover>
  );
}
