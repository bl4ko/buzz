import * as React from "react";

import { useChannelMembersQuery } from "@/features/channels/hooks";
import { useRelayMembersQuery } from "@/features/community-members/hooks";
import { normalizePubkey } from "@/shared/lib/pubkey";

type Member = { pubkey: string; role: string };

export function taskPermissions(input: {
  relayMembers: readonly Member[] | undefined;
  channelMembers: readonly Member[] | undefined;
  currentPubkey: string | undefined;
}) {
  const owners = new Set(
    (input.relayMembers ?? [])
      .filter((m) => m.role === "owner")
      .map((m) => normalizePubkey(m.pubkey)),
  );
  const roles = new Map(
    (input.channelMembers ?? []).map((m) => [
      normalizePubkey(m.pubkey),
      m.role,
    ]),
  );
  const me = normalizePubkey(input.currentPubkey ?? "");
  const canEditTabsFor = (pubkey: string) => {
    const key = normalizePubkey(pubkey);
    return (
      owners.has(key) ||
      roles.get(key) === "owner" ||
      roles.get(key) === "admin"
    );
  };
  return {
    canSetStatus: owners.has(me) || roles.get(me) === "owner",
    canEditTabs: me !== "" && canEditTabsFor(me),
    canEditCanvas:
      owners.has(me) || (roles.has(me) && roles.get(me) !== "guest"),
    canEditTabsFor,
  };
}

export function useTaskPermissions(
  channelId: string | null,
  currentPubkey: string | undefined,
) {
  const relayMembers = useRelayMembersQuery(Boolean(currentPubkey));
  const channelMembers = useChannelMembersQuery(channelId, Boolean(channelId));
  return React.useMemo(
    () =>
      taskPermissions({
        relayMembers: relayMembers.data,
        channelMembers: channelMembers.data,
        currentPubkey,
      }),
    [relayMembers.data, channelMembers.data, currentPubkey],
  );
}
