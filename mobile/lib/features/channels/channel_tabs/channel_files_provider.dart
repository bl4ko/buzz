import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/relay/relay.dart';
import 'files_and_links.dart';

final channelFilesProvider = FutureProvider.autoDispose
    .family<List<FileLinkItem>, String>((ref, channelId) async {
      final events = await ref.read(relaySessionProvider.notifier).queryRelay([
        NostrFilter(
          kinds: const [
            EventKind.streamMessage,
            EventKind.streamMessageV2,
            EventKind.forumPost,
            EventKind.forumComment,
          ],
          tags: {
            '#h': [channelId],
          },
          limit: 200,
          extensions: const {'files_and_links': true},
        ),
      ]);
      return extractFilesAndLinks(events);
    });
