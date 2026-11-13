import * as React from "react";
import { useQuery } from "@tanstack/react-query";

import { relayClient } from "@/shared/api/relayClient";
import type { Channel } from "@/shared/api/types";
import {
  type ChannelLevelResolution,
  type ChannelNotificationLevel,
  EMPTY_NOTIFICATION_AGENT_KEYS,
  latestRosters,
  type NotificationAgentKeys,
  notificationAgentKeys,
  resolveChannelNotificationLevel,
  rosterMemberPubkeys,
} from "./lib/channelLevels";

const KIND_NIP29_GROUP_MEMBERS = 39002;
const ROSTER_LIMIT = 1000;
const PROFILE_BATCH = 200;

async function fetchNotificationAgentKeys(
  pubkey: string,
  channelIds: ReadonlySet<string>,
): Promise<NotificationAgentKeys> {
  const rosters = latestRosters(
    await relayClient.fetchEvents({
      kinds: [KIND_NIP29_GROUP_MEMBERS],
      "#p": [pubkey],
      limit: ROSTER_LIMIT,
    }),
  );
  for (const channelId of [...rosters.keys()]) {
    if (!channelIds.has(channelId)) rosters.delete(channelId);
  }
  const members = [
    ...new Set([...rosters.values()].flatMap(rosterMemberPubkeys)),
  ];
  const profiles = [];
  for (let offset = 0; offset < members.length; offset += PROFILE_BATCH) {
    const authors = members.slice(offset, offset + PROFILE_BATCH);
    profiles.push(
      ...(await relayClient.fetchEvents({
        kinds: [0],
        authors,
        limit: authors.length,
      })),
    );
  }
  return notificationAgentKeys(rosters, profiles);
}

export function useNotificationAgentKeys(
  channels: readonly Channel[],
  pubkey: string | undefined,
): NotificationAgentKeys {
  const channelIds = React.useMemo(
    () =>
      [
        ...new Set(
          channels
            .filter(
              (channel) =>
                channel.channelType !== "dm" &&
                channel.isMember &&
                !channel.archivedAt,
            )
            .map((channel) => channel.id),
        ),
      ].sort(),
    [channels],
  );
  const normalizedPubkey = pubkey?.trim().toLowerCase() ?? "";
  const query = useQuery({
    queryKey: ["notification-agent-keys", normalizedPubkey, channelIds],
    queryFn: () =>
      fetchNotificationAgentKeys(normalizedPubkey, new Set(channelIds)),
    enabled: normalizedPubkey.length > 0 && channelIds.length > 0,
    staleTime: 10 * 60_000,
    placeholderData: (previous) => previous,
  });
  return query.data ?? EMPTY_NOTIFICATION_AGENT_KEYS;
}

export type ChannelNotificationLevels = NotificationAgentKeys & {
  explicitLevels: ReadonlyMap<string, ChannelNotificationLevel>;
  resolve: (
    channel: Pick<Channel, "id" | "channelType">,
  ) => ChannelLevelResolution;
  setLevel: (channelId: string, level: ChannelNotificationLevel | null) => void;
};

export function useChannelNotificationLevelState(
  channels: readonly Channel[],
  pubkey: string | undefined,
  explicitLevels: ReadonlyMap<string, ChannelNotificationLevel>,
  setLevel: ChannelNotificationLevels["setLevel"],
): ChannelNotificationLevels {
  const agentKeys = useNotificationAgentKeys(channels, pubkey);
  return React.useMemo(
    () => ({
      ...agentKeys,
      explicitLevels,
      resolve: (channel) =>
        resolveChannelNotificationLevel(
          channel,
          explicitLevels,
          agentKeys.agentChannelIds,
        ),
      setLevel,
    }),
    [agentKeys, explicitLevels, setLevel],
  );
}
