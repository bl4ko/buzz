import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/theme/buzz_icons.dart';
import '../../../shared/theme/theme.dart';
import '../channel.dart';
import 'message_pins_provider.dart';
import 'pinned_messages_list.dart';

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

class PinnedMessagesPage extends StatelessWidget {
  const PinnedMessagesPage({required this.channel, super.key});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pinned messages')),
      body: PinnedMessagesList(channel: channel),
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
