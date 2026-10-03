import { KIND_HUDDLE_STARTED } from "@/shared/constants/kinds";
import { normalizePubkey } from "@/shared/lib/pubkey";
import type { TimelineMessage } from "@/features/messages/types";
import type { UserProfileLookup } from "@/features/profile/lib/identity";
import { ownsAuthorAgent } from "@/features/profile/lib/identity";

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
  message: TimelineMessage,
  currentPubkey: string | undefined,
  profiles: UserProfileLookup | undefined,
): boolean {
  if (!currentPubkey || !message.pubkey) return false;
  if (normalizePubkey(message.pubkey) === normalizePubkey(currentPubkey))
    return true;
  return ownsAuthorAgent(
    profiles?.[normalizePubkey(message.pubkey)],
    currentPubkey,
  );
}
