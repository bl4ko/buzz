part of '../message_content.dart';

/// Shows signed `p` recipients that the message text does not show.
class MessageNotifiedLine extends ConsumerWidget {
  final String content;
  final List<List<String>> tags;
  final String senderPubkey;
  final String channelId;
  final Map<String, String> mentionNames;
  final Map<String, String> mentionLabels;
  final Set<String> agentMentionPubkeys;
  final void Function(String pubkey)? onMentionTap;

  const MessageNotifiedLine({
    super.key,
    required this.content,
    required this.tags,
    required this.senderPubkey,
    required this.channelId,
    this.mentionNames = const {},
    this.mentionLabels = const {},
    this.agentMentionPubkeys = const {},
    this.onMentionTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDm =
        ref
            .watch(channelsProvider)
            .asData
            ?.value
            .any((channel) => channel.id == channelId && channel.isDm) ??
        false;
    if (isDm) return const SizedBox.shrink();
    final pubkeys = hiddenMentionPubkeys(content, tags, mentionNames, [
      senderPubkey,
    ]);
    if (pubkeys.isEmpty) return const SizedBox.shrink();
    final style = context.textTheme.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    return Padding(
      key: const ValueKey('message-notified'),
      padding: const EdgeInsets.only(top: Grid.half),
      child: Wrap(
        spacing: Grid.half,
        runSpacing: Grid.half,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Notified:', style: style),
          for (final pubkey in pubkeys)
            GestureDetector(
              onTap: onMentionTap == null ? null : () => onMentionTap!(pubkey),
              child: MessageMentionPill(
                label:
                    mentionLabels[pubkey] ??
                    mentionNames[pubkey] ??
                    (pubkey.length > 8 ? '${pubkey.substring(0, 8)}…' : pubkey),
                isAgent: agentMentionPubkeys.contains(pubkey),
                textStyle: style,
              ),
            ),
        ],
      ),
    );
  }
}

String _markdownMentionName(String name) => name.replaceAll(' ', '\u00A0');
