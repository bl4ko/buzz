import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:buzz/shared/theme/buzz_icons.dart';

import '../../shared/relay/relay.dart';
import '../../shared/reminders/reminder_service.dart' as service;
import '../../shared/reminders/reminder_time_presets.dart';
import '../../shared/theme/theme.dart';
import '../channels/channel_detail_page.dart';
import '../channels/channels_provider.dart';
import 'reminders_provider.dart';
import 'inbox_item.dart';

class LaterPage extends ConsumerWidget {
  const LaterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(remindersProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Later'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'In progress'),
              Tab(text: 'Completed'),
              Tab(text: 'Archived'),
            ],
          ),
        ),
        body: query.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: TextButton(
              onPressed: () => ref.invalidate(remindersProvider),
              child: const Text('Could not load saved items. Retry'),
            ),
          ),
          data: (items) => TabBarView(
            children: [
              for (final status in ['pending', 'done', 'cancelled'])
                _LaterList(
                  items: items.where((item) => item.status == status).toList()
                    ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LaterList extends HookConsumerWidget {
  final List<Reminder> items;
  const _LaterList({required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = useState(false);

    Future<void> update(Reminder item, String status, {int? notBefore}) async {
      if (busy.value) return;
      final writer = ref.read(service.reminderServiceProvider);
      if (writer == null) return;
      final community = ref.read(relayConfigProvider);
      busy.value = true;
      try {
        final target = item.target;
        await writer.createReminder(
          target: target == null
              ? null
              : service.ReminderTarget(
                  eventId: target.eventId,
                  channelId: target.channelId,
                  preview: target.preview,
                  authorPubkey: target.authorPubkey,
                ),
          note: item.note,
          status: status,
          dTag: item.id,
          previousCreatedAt: item.createdAt,
          notBefore: notBefore,
        );
        if (!context.mounted || ref.read(relayConfigProvider) != community) {
          return;
        }
        await ref.read(remindersProvider.notifier).refresh();
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not update saved item. Try again.'),
            ),
          );
        }
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    Future<void> open(Reminder item) async {
      final target = item.target;
      if (target == null) return;
      final community = ref.read(relayConfigProvider);
      try {
        final channels = await ref.read(channelsProvider.future);
        final channel = channels
            .where((c) => c.id == target.channelId)
            .firstOrNull;
        if (channel == null) throw StateError('Channel unavailable');
        final events = await ref
            .read(relaySessionProvider.notifier)
            .fetchHistory(
              NostrFilter(
                ids: [target.eventId],
                kinds: EventKind.channelEventKinds,
                limit: 1,
              ),
            );
        if (!context.mounted || ref.read(relayConfigProvider) != community) {
          return;
        }
        final event = events.firstOrNull;
        if (event == null || event.getTagValue('h') != target.channelId) {
          throw StateError('Message unavailable');
        }
        final thread = threadReferenceOf(event.tags);
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChannelDetailPage(
              channel: channel,
              initialMessageId: target.eventId,
              initialThreadRootId: thread.rootId ?? thread.parentId,
              initialThreadRouteBehavior:
                  InitialThreadRouteBehavior.replaceCurrentRoute,
            ),
          ),
        );
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This message is no longer available.'),
            ),
          );
        }
      }
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(remindersProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          Grid.gutter,
          Grid.sm,
          Grid.gutter,
          120 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No items here. Select Save for later from a message menu.',
              ),
            ),
          for (final item in items)
            Card(
              key: ValueKey('later-item-${item.id}'),
              child: Padding(
                padding: const EdgeInsets.all(Grid.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.target?.preview ?? item.note ?? 'Saved item'),
                    if (item.target != null && item.note != null)
                      Text(item.note!),
                    if (item.notBefore != null)
                      Text(
                        'Reminder: ${DateTime.fromMillisecondsSinceEpoch(item.notBefore! * 1000).toLocal()}',
                      ),
                    Wrap(
                      spacing: 4,
                      children: [
                        if (item.target != null)
                          TextButton(
                            onPressed: () => open(item),
                            child: const Text('Open message'),
                          ),
                        TextButton(
                          onPressed: busy.value
                              ? null
                              : () => update(
                                  item,
                                  item.status == 'pending' ? 'done' : 'pending',
                                ),
                          child: Text(
                            item.status == 'pending'
                                ? 'Mark complete'
                                : 'Move to In progress',
                          ),
                        ),
                        if (item.status == 'pending')
                          PopupMenuButton<int>(
                            enabled: !busy.value,
                            tooltip: 'Set reminder',
                            icon: const Icon(BuzzIcons.clock),
                            onSelected: (time) =>
                                update(item, 'pending', notBefore: time),
                            itemBuilder: (_) => [
                              for (final preset in reminderTimePresets)
                                PopupMenuItem(
                                  value: preset.getTimestamp(),
                                  child: Text(preset.label),
                                ),
                            ],
                          ),
                        if (item.status != 'cancelled')
                          TextButton(
                            onPressed: busy.value
                                ? null
                                : () => update(item, 'cancelled'),
                            child: const Text('Archive'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
