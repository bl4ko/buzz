import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../channel.dart';
import 'channel_files_provider.dart';
import 'channel_files_view.dart';
import 'channel_pins_view.dart';
import 'channel_tab_items.dart';
import 'channel_tasks_provider.dart';
import 'channel_tabs_provider.dart';
import 'channel_tasks_view.dart';
import 'custom_tab_view.dart';
import 'thread_status.dart';
import 'files_and_links.dart';

class ChannelTabBody extends ConsumerWidget {
  const ChannelTabBody({
    super.key,
    required this.channel,
    required this.selected,
    required this.permissions,
    required this.onOpenThread,
    required this.onOpenMessage,
  });

  final Channel channel;
  final String selected;
  final TaskPermissions permissions;
  final ValueChanged<String> onOpenThread;
  final void Function(String messageId, String? rootId) onOpenMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (selected == 'tasks') {
      return ChannelTasksView(
        state: ref.watch(channelTasksProvider(channel.id)),
        canSetStatus: permissions.canSetStatus,
        onReact: (eventId, emoji) => ref
            .read(channelTasksProvider(channel.id).notifier)
            .decide(
              eventId,
              emoji == approveEmoji
                  ? OwnerDecision.approve
                  : OwnerDecision.deny,
            ),
        onDone: (task) =>
            ref.read(channelTasksProvider(channel.id).notifier).markDone(task),
        onOpenMessage: onOpenMessage,
      );
    }
    if (selected == 'pins') return ChannelPinsView(channel: channel);
    if (selected == 'files') {
      final items =
          ref.watch(channelFilesProvider(channel.id)).value ??
          const <FileLinkItem>[];
      return ChannelFilesView(
        items: items,
        onOpenMessage: (item) => onOpenMessage(item.messageId, item.rootId),
      );
    }
    if (selected.startsWith('custom:')) {
      final id = selected.substring('custom:'.length);
      final tab = ref
          .watch(channelTabsProvider(channel.id))
          .latest
          .visible
          .where((t) => t.id == id)
          .firstOrNull;
      if (tab == null) return const SizedBox.shrink();
      return CustomTabView(
        channel: channel,
        tab: tab,
        canEditCanvas: permissions.canEditCanvas,
        onOpenMessage: (messageId) => onOpenMessage(messageId, null),
        onOpenThread: onOpenThread,
      );
    }
    return const SizedBox.shrink();
  }
}
