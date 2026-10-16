import { PinOff } from "lucide-react";

import { formatFullDateTime } from "@/features/messages/lib/dateFormatters";
import type { PinnedMessage } from "@/features/messages/lib/messagePins";
import {
  resolveUserLabel,
  type UserProfileLookup,
} from "@/features/profile/lib/identity";
import { resolveEventAuthorPubkey } from "@/shared/lib/authors";
import { normalizePubkey } from "@/shared/lib/pubkey";
import { Button } from "@/shared/ui/button";
import { UserAvatar } from "@/shared/ui/UserAvatar";

export function authorPubkeyOf(item: PinnedMessage) {
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

export function ChannelPinsList({
  pinnedMessages,
  profiles,
  currentPubkey,
  canPin,
  isLoading,
  onOpenMessage,
  onUnpin,
}: {
  pinnedMessages: PinnedMessage[];
  profiles: UserProfileLookup | undefined;
  currentPubkey?: string;
  canPin: boolean;
  isLoading: boolean;
  onOpenMessage: (item: PinnedMessage) => void;
  onUnpin: (item: PinnedMessage) => void;
}) {
  const count = pinnedMessages.length;
  return (
    <div data-testid="channel-pins-panel">
      <div className="border-b border-border/70 px-4 py-3 text-sm font-semibold">
        Pinned messages
      </div>
      {count === 0 ? (
        <p className="px-4 py-6 text-center text-sm text-muted-foreground">
          {isLoading ? "Loading pinned messages…" : "No pinned messages yet."}
        </p>
      ) : (
        <ul className="max-w-3xl py-1">
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
                  onClick={() => onOpenMessage(item)}
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
                {canPin ? (
                  <Button
                    aria-label="Unpin message"
                    className="mt-2 h-7 w-7 shrink-0 p-0"
                    data-testid={`unpin-message-${item.target.id}`}
                    onClick={() => onUnpin(item)}
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
    </div>
  );
}
