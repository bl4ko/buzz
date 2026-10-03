import { useEffect } from "react";
import { useQueryClient } from "@tanstack/react-query";

import { relayMembersQueryKey } from "./hooks";
import { useCommunities } from "@/features/communities/useCommunities";
import { useRelaySelfQuery } from "@/features/moderation/hooks";
import { relayClient } from "@/shared/api/relayClient";
import { relayMembersFromEvent } from "@/shared/api/relayMembers";
import type { RelayEvent, RelayMember } from "@/shared/api/types";
import { normalizePubkey } from "@/shared/lib/pubkey";

const KIND_NIP43_MEMBERSHIP_LIST = 13534;

export function useLiveRelayMembers({
  enabled,
  pubkey,
}: {
  enabled: boolean;
  pubkey: string | undefined;
}) {
  const queryClient = useQueryClient();
  const { activeCommunity } = useCommunities();
  const communityId = activeCommunity?.id ?? null;
  const relayUrl = activeCommunity?.relayUrl ?? null;
  const viewerPubkey = normalizePubkey(pubkey ?? "");
  const active = enabled && !!communityId && !!viewerPubkey;
  const relaySelf = useRelaySelfQuery(active).data;
  const relayPubkey = normalizePubkey(relaySelf ?? "");

  useEffect(() => {
    if (
      !enabled ||
      !communityId ||
      !relayUrl ||
      !viewerPubkey ||
      !relayPubkey
    ) {
      return;
    }
    const controller = new AbortController();
    let disposed = false;
    let unsubscribe = () => {};
    let generation = 0;
    let newestSnapshotAt = 0;
    const sameSecondIds = new Set<string>();
    for (const member of queryClient.getQueryData<RelayMember[]>(
      relayMembersQueryKey,
    ) ?? []) {
      const createdAt = Date.parse(member.createdAt) / 1_000;
      if (Number.isFinite(createdAt)) {
        newestSnapshotAt = Math.max(newestSnapshotAt, createdAt);
      }
    }

    const acceptSnapshot = async (event: RelayEvent) => {
      if (
        disposed ||
        event.kind !== KIND_NIP43_MEMBERSHIP_LIST ||
        normalizePubkey(event.pubkey) !== relayPubkey ||
        event.created_at < newestSnapshotAt ||
        sameSecondIds.has(event.id)
      ) {
        return;
      }
      if (event.created_at > newestSnapshotAt) sameSecondIds.clear();
      newestSnapshotAt = event.created_at;
      sameSecondIds.add(event.id);
      const snapshotGeneration = ++generation;
      const members = relayMembersFromEvent(event);
      await queryClient.cancelQueries({
        queryKey: relayMembersQueryKey,
        exact: true,
      });
      if (disposed || generation !== snapshotGeneration) return;
      queryClient.setQueryData<RelayMember[]>(relayMembersQueryKey, members);
    };

    void relayClient
      .subscribeLive(
        {
          kinds: [KIND_NIP43_MEMBERSHIP_LIST],
          authors: [relayPubkey],
          limit: 1,
        },
        (event) => {
          void acceptSnapshot(event).catch((error) => {
            if (!disposed)
              console.error("Could not update relay members", error);
          });
        },
        undefined,
        undefined,
        controller.signal,
      )
      .then((cleanup) => {
        if (disposed) cleanup();
        else unsubscribe = cleanup;
      })
      .catch((error) => {
        if (!disposed) console.error("Could not observe relay members", error);
      });

    return () => {
      disposed = true;
      controller.abort();
      unsubscribe();
    };
  }, [communityId, enabled, queryClient, relayPubkey, relayUrl, viewerPubkey]);
}
