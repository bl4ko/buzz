import { useChannelMembersQuery } from "@/features/channels/hooks";
import { useRelayMembersQuery } from "@/features/community-members/hooks";
import { normalizePubkey } from "@/shared/lib/pubkey";
import { canModerateChannelMessages } from "./canManageMessage";

export function useMessageModerationPermission(
  channelId: string | null | undefined,
  currentPubkey: string | undefined,
): boolean {
  const communityMembers = useRelayMembersQuery(!!currentPubkey);
  const communityRole = communityMembers.data?.find(
    (member) =>
      normalizePubkey(member.pubkey) === normalizePubkey(currentPubkey ?? ""),
  )?.role;
  const members = useChannelMembersQuery(
    channelId ?? null,
    !!currentPubkey && communityRole !== "owner" && communityRole !== "admin",
  );
  return (
    !!channelId &&
    canModerateChannelMessages(currentPubkey, members.data, communityRole)
  );
}
