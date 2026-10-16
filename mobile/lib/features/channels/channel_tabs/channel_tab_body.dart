import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../channel.dart';
import '../channel_management_provider.dart';
import 'channel_pins_view.dart';
import 'channel_tab_items.dart';
import 'channel_tasks_provider.dart';
import 'channel_tasks_view.dart';

class ChannelTabBody extends ConsumerWidget {
  const ChannelTabBody({
    super.key,
    required this.channel,
    required this.selected,
    required this.permissions,
    required this.onOpenThread,
  });

  final Channel channel;
  final String selected;
  final TaskPermissions permissions;
  final ValueChanged<String> onOpenThread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (selected == 'tasks') {
      return ChannelTasksView(
        state: ref.watch(channelTasksProvider(channel.id)),
        canSetStatus: permissions.canSetStatus,
        onReact: (eventId, emoji) =>
            ref.read(channelActionsProvider).addReaction(eventId, emoji),
        onDone: (task) =>
            ref.read(channelTasksProvider(channel.id).notifier).markDone(task),
        onOpenThread: onOpenThread,
      );
    }
    if (selected == 'pins') return ChannelPinsView(channel: channel);
    return const SizedBox.shrink();
  }
}
