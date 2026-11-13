import type { RelayEvent } from "@/shared/api/types";
import { hasMentionForEvent } from "@/features/notifications/lib/shouldNotify";
import {
  isBroadcastReply,
  isThreadReply,
} from "@/features/messages/lib/threading";

export const CHANNEL_NOTIFICATION_LEVELS = [
  "all",
  "mentions",
  "nothing",
] as const;
export type ChannelNotificationLevel =
  (typeof CHANNEL_NOTIFICATION_LEVELS)[number];

export const CHANNEL_NOTIFICATION_LEVEL_LABELS: Record<
  ChannelNotificationLevel,
  string
> = {
  all: "All new messages",
  mentions: "Mentions and DMs",
  nothing: "Nothing",
};

export function isChannelNotificationLevel(
  value: unknown,
): value is ChannelNotificationLevel {
  return (
    typeof value === "string" &&
    (CHANNEL_NOTIFICATION_LEVELS as readonly string[]).includes(value)
  );
}

export type NotificationAgentKeys = {
  botPubkeys: ReadonlySet<string>;
  agentChannelIds: ReadonlySet<string>;
};

export const EMPTY_NOTIFICATION_AGENT_KEYS: NotificationAgentKeys = {
  botPubkeys: new Set(),
  agentChannelIds: new Set(),
};

export type ChannelLevelResolution = {
  level: ChannelNotificationLevel;
  isExplicit: boolean;
  defaultLevel: ChannelNotificationLevel;
};

export function defaultChannelNotificationLevel(
  channel: { id: string; channelType: string },
  agentChannelIds: ReadonlySet<string>,
): ChannelNotificationLevel {
  if (channel.channelType === "dm") return "all";
  return agentChannelIds.has(channel.id) ? "mentions" : "all";
}

export function resolveChannelNotificationLevel(
  channel: { id: string; channelType: string },
  explicitLevels: ReadonlyMap<string, ChannelNotificationLevel>,
  agentChannelIds: ReadonlySet<string>,
): ChannelLevelResolution {
  const defaultLevel = defaultChannelNotificationLevel(
    channel,
    agentChannelIds,
  );
  const explicit = explicitLevels.get(channel.id);
  return explicit
    ? { level: explicit, isExplicit: true, defaultLevel }
    : { level: defaultLevel, isExplicit: false, defaultLevel };
}

export function isApprovalRequest(event: Pick<RelayEvent, "tags">): boolean {
  return event.tags.some(
    (tag) => tag[0] === "notification" && tag[1] === "approval",
  );
}

export function shouldAlertForChannelMessage(
  event: RelayEvent,
  currentPubkey: string,
  context: {
    resolution: ChannelLevelResolution;
    isDm: boolean;
    botPubkeys: ReadonlySet<string>;
  },
): boolean {
  const { resolution, isDm, botPubkeys } = context;
  if (resolution.level === "nothing") return false;
  if (
    isDm ||
    hasMentionForEvent(event, currentPubkey) ||
    isBroadcastReply(event.tags) ||
    isApprovalRequest(event) ||
    isThreadReply(event.tags)
  ) {
    return true;
  }
  if (resolution.level === "mentions") return false;
  return resolution.isExplicit || !botPubkeys.has(event.pubkey.toLowerCase());
}

export function isBotProfile(event: Pick<RelayEvent, "content">): boolean {
  try {
    const content = JSON.parse(event.content);
    return (
      typeof content === "object" && content !== null && content.bot === true
    );
  } catch {
    return false;
  }
}

export function rosterMemberPubkeys(roster: RelayEvent): string[] {
  return roster.tags
    .filter((tag) => tag[0] === "p" && typeof tag[1] === "string")
    .map((tag) => tag[1].toLowerCase());
}

export function latestRosters(
  rosters: readonly RelayEvent[],
): Map<string, RelayEvent> {
  const latest = new Map<string, RelayEvent>();
  for (const roster of rosters) {
    const channelId = roster.tags.find((tag) => tag[0] === "d")?.[1];
    if (!channelId) continue;
    const current = latest.get(channelId);
    if (!current || roster.created_at > current.created_at) {
      latest.set(channelId, roster);
    }
  }
  return latest;
}

export function notificationAgentKeys(
  rosters: ReadonlyMap<string, RelayEvent>,
  profiles: readonly RelayEvent[],
): NotificationAgentKeys {
  const botPubkeys = new Set(
    profiles.filter(isBotProfile).map((event) => event.pubkey.toLowerCase()),
  );
  const agentChannelIds = new Set<string>();
  for (const [channelId, roster] of rosters) {
    if (rosterMemberPubkeys(roster).some((pubkey) => botPubkeys.has(pubkey))) {
      agentChannelIds.add(channelId);
    }
  }
  return { botPubkeys, agentChannelIds };
}
