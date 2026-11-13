import { Bell, Check } from "lucide-react";

import {
  CHANNEL_NOTIFICATION_LEVEL_LABELS,
  CHANNEL_NOTIFICATION_LEVELS,
} from "@/features/notifications/lib/channelLevels";
import type { ChannelNotificationLevels } from "@/features/notifications/useChannelNotificationLevels";
import {
  ContextMenuIconSlot,
  deferMenuAction,
} from "@/features/sidebar/ui/sidebarMenuHelpers";
import type { Channel } from "@/shared/api/types";
import {
  ContextMenuItem,
  ContextMenuSeparator,
  ContextMenuSub,
  ContextMenuSubContent,
  ContextMenuSubTrigger,
} from "@/shared/ui/context-menu";

export function ChannelNotificationLevelSubmenu({
  channel,
  levels,
}: {
  channel: Pick<Channel, "id" | "channelType">;
  levels: ChannelNotificationLevels;
}) {
  const resolution = levels.resolve(channel);
  return (
    <ContextMenuSub>
      <ContextMenuSubTrigger data-testid="channel-notification-level-menu">
        <ContextMenuIconSlot>
          <Bell className="h-4 w-4" />
        </ContextMenuIconSlot>
        <span>Notify me about</span>
      </ContextMenuSubTrigger>
      <ContextMenuSubContent>
        {CHANNEL_NOTIFICATION_LEVELS.map((level) => (
          <ContextMenuItem
            data-testid={`channel-notification-level-${level}`}
            key={level}
            onSelect={() =>
              deferMenuAction(() => levels.setLevel(channel.id, level))
            }
          >
            <ContextMenuIconSlot>
              {resolution.isExplicit && resolution.level === level ? (
                <Check className="h-4 w-4" />
              ) : null}
            </ContextMenuIconSlot>
            <span>{CHANNEL_NOTIFICATION_LEVEL_LABELS[level]}</span>
          </ContextMenuItem>
        ))}
        <ContextMenuSeparator />
        <ContextMenuItem
          data-testid="channel-notification-level-default"
          onSelect={() =>
            deferMenuAction(() => levels.setLevel(channel.id, null))
          }
        >
          <ContextMenuIconSlot>
            {resolution.isExplicit ? null : <Check className="h-4 w-4" />}
          </ContextMenuIconSlot>
          <span>
            Default (
            {CHANNEL_NOTIFICATION_LEVEL_LABELS[resolution.defaultLevel]})
          </span>
        </ContextMenuItem>
      </ContextMenuSubContent>
    </ContextMenuSub>
  );
}
