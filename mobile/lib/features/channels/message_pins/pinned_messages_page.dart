import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/theme/buzz_icons.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/buzz_loading_indicator.dart';
import '../../activity/inbox_item.dart';
import '../channel.dart';
import '../channel_detail_page.dart';
import '../channel_identity_names_provider.dart';
import '../date_formatters.dart';
import '../timeline_message.dart';
import 'message_pins_provider.dart';

Future<void> showPinnedMessagesPage(BuildContext context, Channel channel) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PinnedMessagesPage(channel: channel),
      ),
    );

Future<void> updateMessagePin(
  BuildContext context,
  WidgetRef ref, {
  required String channelId,
  required String messageId,
  required bool pinned,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref
        .read(channelMessagePinsProvider(channelId).notifier)
        .setPinned(messageId, pinned: pinned);
  } catch (_) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          pinned ? 'Could not pin message.' : 'Could not unpin message.',
        ),
      ),
    );
  }
}

class PinnedMessagesPage extends HookConsumerWidget {
  const PinnedMessagesPage({required this.channel, super.key});

  final Channel channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pins = ref.watch(channelPinnedMessagesProvider(channel.id));
    final ids = [for (final pin in pins) pin.targetId]..sort();
    final targetsAsync = ref.watch(
      pinnedMessageTargetsProvider((channel.id, ids.join(','))),
    );
    final resolved = useRef(<String, TimelineMessage>{});
    final value = targetsAsync.value;
    if (value != null) resolved.value = value;
    final targets = value ?? resolved.value;
    final waiting = value == null && !targetsAsync.hasError && pins.isNotEmpty;
    final rows = [
      for (final pin in pins)
        if (targets[pin.targetId] case final message?) (pin, message),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Pinned messages')),
      body: rows.isEmpty
          ? Center(
              child: waiting
                  ? const BuzzLoadingIndicator(
                      size: 24,
                      semanticLabel: 'Loading pinned messages',
                    )
                  : Padding(
                      padding: const EdgeInsets.all(Grid.gutter),
                      child: Text(
                        targetsAsync.hasError
                            ? 'Pinned messages are unavailable.'
                            : 'No pinned messages yet. Pin a message from its menu.',
                        textAlign: TextAlign.center,
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ),
            )
          : ListView.separated(
              key: const ValueKey('pinned-messages-list'),
              padding: EdgeInsets.only(
                top: Grid.xs,
                bottom: MediaQuery.viewPaddingOf(context).bottom + Grid.xs,
              ),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final (pin, message) = rows[index];
                return _PinnedMessageRow(
                  key: ValueKey('pinned-message-${message.id}'),
                  channel: channel,
                  pin: pin,
                  message: message,
                );
              },
            ),
    );
  }
}

class _PinnedMessageRow extends ConsumerWidget {
  const _PinnedMessageRow({
    required this.channel,
    required this.pin,
    required this.message,
    super.key,
  });

  final Channel channel;
  final MessagePinEvent pin;
  final TimelineMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final author = watchChannelIdentityLabel(ref, channel.id, message.pubkey);
    final canUnpin = channel.isMember && !channel.isArchived;
    final preview = message.content.trim().isEmpty
        ? (message.hasAttachments ? 'Attachment' : 'Message')
        : message.content.trim();

    Future<void> unpin() => updateMessagePin(
      context,
      ref,
      channelId: channel.id,
      messageId: message.id,
      pinned: false,
    );

    void open() {
      final threadRootId = isBroadcastReply(message.tags)
          ? null
          : message.rootId ?? message.parentId;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChannelDetailPage(
            channel: channel,
            initialMessageId: message.id,
            initialThreadRootId: threadRootId,
            initialThreadRouteBehavior:
                InitialThreadRouteBehavior.replaceCurrentRoute,
            markChannelReadOnOpen: false,
          ),
        ),
      );
    }

    final tile = ListTile(
      onTap: open,
      title: Row(
        children: [
          Flexible(
            child: Text(
              author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.titleSmall,
            ),
          ),
          const SizedBox(width: Grid.xs),
          Text(
            relativeTime(message.createdAt),
            style: context.textTheme.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
      subtitle: Text(preview, maxLines: 3, overflow: TextOverflow.ellipsis),
      trailing: canUnpin
          ? IconButton(
              key: ValueKey('unpin-message-${message.id}'),
              tooltip: 'Unpin',
              icon: const Icon(BuzzIcons.pinOff, size: 20),
              onPressed: unpin,
            )
          : null,
    );
    if (!canUnpin) return tile;
    return Dismissible(
      key: ValueKey('pinned-dismiss-${pin.id}'),
      direction: DismissDirection.endToStart,
      background: ColoredBox(
        color: context.colors.errorContainer,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Grid.gutter),
            child: Text(
              'Unpin',
              style: TextStyle(color: context.colors.onErrorContainer),
            ),
          ),
        ),
      ),
      confirmDismiss: (_) async {
        await unpin();
        return false;
      },
      child: tile,
    );
  }
}

class MessagePinnedLabel extends StatelessWidget {
  const MessagePinnedLabel({required this.messageId, super.key});

  final String messageId;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.onSurfaceVariant;
    return Row(
      key: ValueKey('message-pinned-$messageId'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(BuzzIcons.pin, size: 14, color: color),
        const SizedBox(width: Grid.half),
        Text(
          'Pinned',
          style: context.textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
