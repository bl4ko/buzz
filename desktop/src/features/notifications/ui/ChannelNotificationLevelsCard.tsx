import { useAppShell } from "@/app/AppShellContext";
import { useChannelsQuery } from "@/features/channels/hooks";
import {
  CHANNEL_NOTIFICATION_LEVEL_LABELS,
  CHANNEL_NOTIFICATION_LEVELS,
} from "@/features/notifications/lib/channelLevels";
import {
  SettingsOptionGroup,
  SettingsOptionRow,
} from "@/features/settings/ui/SettingsOptionGroup";
import { Button } from "@/shared/ui/button";
import { SegmentedControl } from "@/shared/ui/segmented-control";

const LEVEL_OPTIONS = CHANNEL_NOTIFICATION_LEVELS.map((level) => ({
  value: level,
  label: { all: "All", mentions: "Mentions", nothing: "Nothing" }[level],
}));

export function ChannelNotificationLevelsCard() {
  const { channelNotificationLevels: levels } = useAppShell();
  const channelsQuery = useChannelsQuery();
  if (!levels) return null;
  const channels = (channelsQuery.data ?? [])
    .filter(
      (channel) =>
        channel.channelType !== "dm" && channel.isMember && !channel.archivedAt,
    )
    .sort((left, right) => left.name.localeCompare(right.name));

  return (
    <SettingsOptionGroup
      data-testid="settings-channel-notification-levels"
      description="All new messages, Mentions and DMs, or Nothing for each channel. Channels with agents default to Mentions and DMs. Posts from agents notify only in channels set to All. Direct messages, mentions, approvals, and replies in your threads always notify unless the channel is set to Nothing. The phone uses the same levels."
      title="Channels"
    >
      {channels.length === 0 ? (
        <SettingsOptionRow>
          <p className="text-sm text-muted-foreground/70">No channels.</p>
        </SettingsOptionRow>
      ) : null}
      {channels.map((channel) => {
        const resolution = levels.resolve(channel);
        return (
          <SettingsOptionRow
            data-testid={`channel-notification-level-row-${channel.id}`}
            key={channel.id}
          >
            <div className="min-w-0">
              <p className="truncate text-sm font-medium">#{channel.name}</p>
              <p
                className="text-sm font-normal text-muted-foreground/70"
                data-settings-subcopy
              >
                {resolution.isExplicit ? (
                  <>
                    Set by you. Default:{" "}
                    {CHANNEL_NOTIFICATION_LEVEL_LABELS[resolution.defaultLevel]}
                    .{" "}
                    <Button
                      className="h-auto p-0 text-sm"
                      data-testid={`channel-notification-level-reset-${channel.id}`}
                      onClick={() => levels.setLevel(channel.id, null)}
                      type="button"
                      variant="link"
                    >
                      Use default
                    </Button>
                  </>
                ) : (
                  `Default${levels.agentChannelIds.has(channel.id) ? " for a channel with agents" : ""}: ${CHANNEL_NOTIFICATION_LEVEL_LABELS[resolution.defaultLevel]}`
                )}
              </p>
            </div>
            <SegmentedControl
              legend={`Notifications for #${channel.name}`}
              onValueChange={(level) => levels.setLevel(channel.id, level)}
              optionTestIdPrefix={`channel-notification-level-${channel.id}`}
              options={LEVEL_OPTIONS}
              size="wide"
              testId={`channel-notification-level-control-${channel.id}`}
              value={resolution.level}
            />
          </SettingsOptionRow>
        );
      })}
    </SettingsOptionGroup>
  );
}
