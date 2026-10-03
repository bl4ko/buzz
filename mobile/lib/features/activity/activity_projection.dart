import '../../shared/relay/nostr_models.dart';
import '../channels/unread_badge/should_notify_for_event.dart';
import 'feed_item.dart';

HomeFeedResponse buildActivityFeed(
  List<NostrEvent> events, {
  required String myPubkey,
  required Set<String> channelIds,
  Set<String> mutedChannelIds = const {},
  Set<String> interestedRootIds = const {},
}) {
  final myPk = myPubkey.toLowerCase();
  final byId = {for (final event in events) event.id: event};
  final deletedIds = {
    for (final event in events)
      if (event.kind == EventKind.deletion ||
          event.kind == EventKind.nip29DeleteEvent)
        for (final tag in event.tags)
          if (tag.length > 1 && tag[0] == 'e') tag[1],
  };
  final rootIds = {
    ...interestedRootIds,
    for (final event in events)
      if (event.pubkey.toLowerCase() == myPk &&
          EventKind.channelMessageEventKinds.contains(event.kind))
        event.threadReference.rootId ?? event.id,
  };
  final latestEdits = <String, NostrEvent>{};
  for (final event in events) {
    if (event.kind != EventKind.streamMessageEdit) continue;
    for (final tag in event.tags) {
      if (tag.length < 2 || tag[0] != 'e') continue;
      final previous = latestEdits[tag[1]];
      if (previous == null || event.createdAt > previous.createdAt) {
        latestEdits[tag[1]] = event;
      }
    }
  }
  final items = <FeedItem>[];
  for (final event in byId.values) {
    if (deletedIds.contains(event.id)) continue;
    final addressed = event.tags.any(
      (tag) => tag.length > 1 && tag[0] == 'p' && tag[1].toLowerCase() == myPk,
    );
    final fromOther = event.pubkey.toLowerCase() != myPk;
    String? category;
    NostrEvent? target;
    if (const {46010, 46011, 46012}.contains(event.kind) && addressed) {
      category = 'needs_action';
    } else if (const {
          43001,
          43002,
          43003,
          43004,
          43005,
          43006,
        }.contains(event.kind) &&
        addressed) {
      category = 'agent_activity';
    } else if (event.kind == EventKind.reaction && fromOther) {
      final targetId = event.tags
          .where((tag) => tag.length > 1 && tag[0] == 'e')
          .lastOrNull?[1];
      target = byId[targetId];
      if (target == null ||
          target.pubkey.toLowerCase() != myPk ||
          deletedIds.contains(target.id) ||
          !EventKind.channelMessageEventKinds.contains(target.kind) ||
          !channelIds.contains(target.channelId)) {
        continue;
      }
      category = 'reaction';
    } else if (fromOther &&
        (EventKind.channelMessageEventKinds.contains(event.kind) ||
            event.kind == EventKind.note)) {
      if (addressed) {
        category = 'mention';
      } else if (channelIds.contains(event.channelId) &&
          shouldNotifyForEvent(
            event,
            myPk,
            followedRootIds: rootIds,
            mutedChannelIds: mutedChannelIds,
          )) {
        category = 'activity';
      }
    }
    if (category == null) continue;
    items.add(
      FeedItem(
        id: event.id,
        kind: event.kind,
        pubkey: event.pubkey,
        content: latestEdits[event.id]?.content ?? event.content,
        createdAt: event.createdAt,
        channelId: target?.channelId ?? event.channelId,
        channelName: '',
        tags: event.tags,
        category: category,
        targetEventId: target?.id,
        targetThreadRootId: target?.threadReference.rootId,
        targetContent: target == null
            ? null
            : latestEdits[target.id]?.content ?? target.content,
      ),
    );
  }
  items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return HomeFeedResponse(
    mentions: items.where((item) => item.category == 'mention').toList(),
    needsAction: items
        .where((item) => item.category == 'needs_action')
        .toList(),
    activity: items
        .where((item) => const {'activity', 'reaction'}.contains(item.category))
        .toList(),
    agentActivity: items
        .where((item) => item.category == 'agent_activity')
        .toList(),
  );
}
