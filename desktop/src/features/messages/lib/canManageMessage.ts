import { KIND_HUDDLE_STARTED } from "@/shared/constants/kinds";
import { normalizePubkey } from "@/shared/lib/pubkey";
import type { TimelineMessage } from "@/features/messages/types";
import type { UserProfileLookup } from "@/features/profile/lib/identity";
import { ownsAuthorAgent } from "@/features/profile/lib/identity";
import type { ChannelMember, RelayMemberRole } from "@/shared/api/types";

export function canModerateChannelMessages(
  currentPubkey: string | undefined,
  members: ChannelMember[] | undefined,
  communityRole: RelayMemberRole | undefined,
): boolean {
  if (!currentPubkey) return false;
  if (communityRole === "owner" || communityRole === "admin") return true;
  const role = members?.find(
    (member) =>
      normalizePubkey(member.pubkey) === normalizePubkey(currentPubkey),
  )?.role;
  return role === "owner" || role === "admin";
}

export function canManageMessageForCurrentUser(
  message: TimelineMessage,
  currentPubkey: string | undefined,
  profiles: UserProfileLookup | undefined,
): boolean {
  return (
    message.kind !== KIND_HUDDLE_STARTED &&
    canDeleteMessageForCurrentUser(message, currentPubkey, profiles)
  );
}

export function canDeleteMessageForCurrentUser(
  message: Pick<TimelineMessage, "pubkey">,
  currentPubkey: string | undefined,
  profiles: UserProfileLookup | undefined,
  canModerate = false,
): boolean {
  if (!currentPubkey || !message.pubkey) return false;
  if (canModerate) return true;
  if (normalizePubkey(message.pubkey) === normalizePubkey(currentPubkey))
    return true;
  return ownsAuthorAgent(
    profiles?.[normalizePubkey(message.pubkey)],
    currentPubkey,
  );
}
