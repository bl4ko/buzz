import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/relay/relay.dart';
import '../../../shared/theme/theme.dart';
import '../channel.dart';
import 'canvas_doc_view.dart';
import 'channel_tabs_model.dart';
import 'search_tab.dart';

final _threadTabProvider = FutureProvider.autoDispose
    .family<List<NostrEvent>, (String, String)>((ref, key) async {
      final (channelId, rootId) = key;
      final session = ref.read(relaySessionProvider.notifier);
      final results = await Future.wait([
        session.fetchHistory(
          NostrFilter(
            ids: [rootId],
            kinds: const [
              EventKind.streamMessage,
              EventKind.streamMessageV2,
              EventKind.forumPost,
            ],
            limit: 1,
          ),
        ),
        session.fetchHistory(
          NostrFilter(
            kinds: const [EventKind.streamMessage, EventKind.streamMessageV2],
            tags: {
              '#h': [channelId],
              '#e': [rootId],
            },
            limit: 200,
          ),
        ),
      ]);
      return [...results[0], ...results[1]]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    });

class CustomTabView extends ConsumerWidget {
  const CustomTabView({
    super.key,
    required this.channel,
    required this.tab,
    required this.canEditCanvas,
    required this.onOpenMessage,
    required this.onOpenThread,
  });

  final Channel channel;
  final ChannelTab tab;
  final bool canEditCanvas;
  final void Function(String messageId) onOpenMessage;
  final ValueChanged<String> onOpenThread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (validateTabValue(tab.type, tab.value) != null) {
      return const Center(child: Text('This tab has an invalid value.'));
    }
    switch (tab.type) {
      case 'link':
        return Center(
          child: FilledButton(
            onPressed: () => launchUrl(
              Uri.parse(tab.value),
              mode: LaunchMode.inAppBrowserView,
            ),
            child: Text('Open ${Uri.parse(tab.value).host}'),
          ),
        );
      case 'search':
        final results =
            ref
                .watch(searchTabResultsProvider((channel.id, tab.value)))
                .value ??
            const <NostrEvent>[];
        return ListView(
          children: [
            for (final event in results)
              ListTile(
                title: GptMarkdown(event.content),
                onTap: () => onOpenMessage(event.id),
              ),
            if (results.isEmpty)
              const Padding(
                padding: EdgeInsets.all(Grid.sm),
                child: Text('No messages match.'),
              ),
          ],
        );
      case 'thread':
        final events =
            ref.watch(_threadTabProvider((channel.id, tab.value))).value ??
            const <NostrEvent>[];
        return ListView(
          children: [
            TextButton(
              onPressed: () => onOpenThread(tab.value),
              child: const Text('Open thread'),
            ),
            for (final event in events)
              ListTile(title: GptMarkdown(event.content)),
          ],
        );
      case 'canvas':
        return CanvasDocView(
          channelId: channel.id,
          canvasId: tab.value,
          canEdit: canEditCanvas,
        );
    }
    return const SizedBox.shrink();
  }
}
