import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/relay/relay.dart';
import '../channel_management_provider.dart';

class SearchTabQuery {
  const SearchTabQuery({required this.text, this.authors, this.unresolved});
  final String text;
  final List<String>? authors;
  final String? unresolved;
}

final _from = RegExp(r'(?:^|\s)from:(\S+)');

SearchTabQuery resolveSearchTab(
  String value,
  Iterable<({String pubkey, String? displayName})> members,
) {
  final match = _from.firstMatch(value);
  final text = value.replaceAll(_from, ' ').trim();
  if (match == null) return SearchTabQuery(text: text);
  final raw = match.group(1)!;
  final wanted = raw.replaceFirst('@', '').toLowerCase();
  for (final member in members) {
    if (member.pubkey.toLowerCase() == wanted ||
        (member.displayName ?? '').toLowerCase() == wanted) {
      return SearchTabQuery(text: text, authors: [member.pubkey]);
    }
  }
  return SearchTabQuery(text: text, unresolved: raw);
}

NostrFilter? searchTabFilter(String channelId, SearchTabQuery query) {
  if (query.unresolved != null) return null;
  if (query.text.isEmpty && query.authors == null) return null;
  return NostrFilter(
    kinds: const [
      EventKind.streamMessage,
      EventKind.streamMessageV2,
      EventKind.forumPost,
      EventKind.forumComment,
    ],
    authors: query.authors,
    search: query.text.isEmpty ? null : query.text,
    tags: {
      '#h': [channelId],
    },
    limit: 50,
  );
}

final searchTabResultsProvider = FutureProvider.autoDispose
    .family<List<NostrEvent>, (String, String)>((ref, key) async {
      final (channelId, value) = key;
      final members = await ref.watch(channelMembersProvider(channelId).future);
      final query = resolveSearchTab(
        value,
        members.map((m) => (pubkey: m.pubkey, displayName: m.displayName)),
      );
      final filter = searchTabFilter(channelId, query);
      if (filter == null) return const [];
      return ref.read(relaySessionProvider.notifier).fetchHistory(filter);
    });
