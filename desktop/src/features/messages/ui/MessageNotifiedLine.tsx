import type { UserProfileLookup } from "@/features/profile/lib/identity";
import { UserProfilePopover } from "@/features/profile/ui/UserProfilePopover";
import { truncateNpub } from "@/shared/lib/pubkey";
import { InlineChip } from "@/shared/ui/InlineChip";
import { MESSAGE_MARKDOWN_CLASS } from "@/shared/ui/mentionChip";

/** Signed `p` recipients that the message text does not show. */
export function MessageNotifiedLine({
  profiles,
  pubkeys,
  isKnownAgentPubkey,
}: {
  profiles?: UserProfileLookup;
  pubkeys: readonly string[];
  isKnownAgentPubkey: (pubkey: string) => boolean;
}) {
  if (pubkeys.length === 0) return null;
  return (
    <div
      className={`${MESSAGE_MARKDOWN_CLASS} mt-1 flex min-w-0 flex-wrap items-center gap-1.5 text-sm font-normal leading-4 text-muted-foreground/70`}
      data-testid="message-notified"
    >
      <span className="shrink-0">Notified:</span>
      {pubkeys.map((pubkey) => {
        const profile = profiles?.[pubkey];
        const label =
          profile?.displayName?.trim() ||
          profile?.name?.trim() ||
          truncateNpub(pubkey);
        const isAgent = isKnownAgentPubkey(pubkey) || profile?.isAgent === true;
        return (
          <UserProfilePopover
            key={pubkey}
            botIdenticonValue={isAgent ? label : undefined}
            pubkey={pubkey}
            role={isAgent ? "bot" : undefined}
            triggerElement="span"
          >
            <InlineChip
              className={isAgent ? "agent-mention-highlight" : undefined}
              data-mention=""
              icon={isAgent ? "agent" : "human"}
              interactive
            >
              {label}
            </InlineChip>
          </UserProfilePopover>
        );
      })}
    </div>
  );
}
