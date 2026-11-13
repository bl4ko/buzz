import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/theme/buzz_icons.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/modal_presentation.dart';
import '../../../shared/widgets/sheet_action_section.dart';
import '../channel.dart';
import 'channel_mutes_provider.dart';
import 'channel_mutes_storage.dart';
import 'channel_notification_levels.dart';

typedef ChannelNotificationLevelResolution = ({
  ChannelNotificationLevel level,
  bool isExplicit,
  ChannelNotificationLevel fallback,
});

ChannelNotificationLevelResolution resolveChannelNotificationLevel(
  ChannelMuteEntry? entry,
  Channel channel,
  NotificationAgentKeys? keys,
) {
  final explicit = entry?.explicitLevel;
  final fallback = defaultChannelNotificationLevel(
    channel,
    keys ?? const NotificationAgentKeys(),
  );
  return (
    level: explicit ?? fallback,
    isExplicit: explicit != null,
    fallback: fallback,
  );
}

String channelNotificationLevelSummary(WidgetRef ref, Channel channel) {
  final resolved = resolveChannelNotificationLevel(
    ref.watch(channelMutesProvider).store.channels[channel.id],
    channel,
    ref.watch(notificationAgentKeysProvider).value,
  );
  return resolved.isExplicit
      ? resolved.level.label
      : '${resolved.level.label} (default)';
}

Future<void> showChannelNotificationLevelSheet(
  BuildContext context,
  ProviderContainer container,
  Channel channel,
) async {
  final resolved = resolveChannelNotificationLevel(
    container.read(channelMutesProvider).store.channels[channel.id],
    channel,
    container.read(notificationAgentKeysProvider).value,
  );
  final notifier = container.read(channelMutesProvider.notifier);
  await showBuzzModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      Widget option(
        String key,
        String title,
        bool selected,
        ChannelNotificationLevel? level,
      ) => ListTile(
        key: ValueKey('channel-notification-level-$key'),
        title: Text(title),
        trailing: selected
            ? Icon(BuzzIcons.check, color: sheetContext.colors.primary)
            : null,
        onTap: () {
          Navigator.of(sheetContext).pop();
          notifier.setChannelLevel(channel.id, level);
        },
      );
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Grid.gutter,
            0,
            Grid.gutter,
            Grid.xs,
          ),
          child: SheetActionSection(
            children: [
              for (final level in ChannelNotificationLevel.values)
                option(
                  level.name,
                  level.label,
                  resolved.isExplicit && resolved.level == level,
                  level,
                ),
              option(
                'default',
                'Default (${resolved.fallback.label})',
                !resolved.isExplicit,
                null,
              ),
            ],
          ),
        ),
      );
    },
  );
}
