import 'package:flutter/foundation.dart';

import '../../../shared/relay/relay.dart';

@immutable
class MessagePinEvent {
  const MessagePinEvent({
    required this.id,
    required this.targetId,
    required this.pubkey,
    required this.createdAt,
    required this.pinned,
  });

  final String id;
  final String targetId;
  final String pubkey;
  final int createdAt;
  final bool pinned;

  static MessagePinEvent? fromEvent(
    NostrEvent event, {
    required String channelId,
  }) {
    if (event.kind != EventKind.streamMessagePinned) return null;
    final channels = <String>[];
    final targets = <String>[];
    final statuses = <String>[];
    for (final tag in event.tags) {
      if (tag.length < 2) continue;
      switch (tag[0]) {
        case 'h':
          channels.add(tag[1]);
        case 'e':
          targets.add(tag[1]);
        case 'status':
          statuses.add(tag[1]);
      }
    }
    if (channels.length != 1 || channels.single != channelId) return null;
    if (targets.length != 1 || targets.single.isEmpty) return null;
    if (statuses.length != 1) return null;
    final status = statuses.single;
    if (status != 'pinned' && status != 'unpinned') return null;
    return MessagePinEvent(
      id: event.id,
      targetId: targets.single,
      pubkey: event.pubkey,
      createdAt: event.createdAt,
      pinned: status == 'pinned',
    );
  }

  bool supersedes(MessagePinEvent other) => createdAt != other.createdAt
      ? createdAt > other.createdAt
      : id.compareTo(other.id) < 0;
}

@immutable
class ChannelMessagePins {
  const ChannelMessagePins([this.latestByTarget = const {}]);

  final Map<String, MessagePinEvent> latestByTarget;

  bool isPinned(String eventId) => latestByTarget[eventId]?.pinned ?? false;

  ChannelMessagePins apply(MessagePinEvent pin) {
    final current = latestByTarget[pin.targetId];
    if (current != null && (current.id == pin.id || !pin.supersedes(current))) {
      return this;
    }
    return ChannelMessagePins({...latestByTarget, pin.targetId: pin});
  }

  List<MessagePinEvent> pinned({Set<String> deletedIds = const {}}) =>
      [
        for (final pin in latestByTarget.values)
          if (pin.pinned && !deletedIds.contains(pin.targetId)) pin,
      ]..sort((left, right) {
        if (left.supersedes(right)) return -1;
        if (right.supersedes(left)) return 1;
        return 0;
      });

  int nextCreatedAt(String targetId, int now) {
    final latest = latestByTarget[targetId]?.createdAt;
    return latest == null || latest < now ? now : latest + 1;
  }
}

ChannelMessagePins reduceMessagePins(
  Iterable<NostrEvent> events, {
  required String channelId,
}) {
  var pins = const ChannelMessagePins();
  for (final event in events) {
    final pin = MessagePinEvent.fromEvent(event, channelId: channelId);
    if (pin != null) pins = pins.apply(pin);
  }
  return pins;
}

Set<String> deletedEventIds(Iterable<NostrEvent> events) => {
  for (final event in events)
    if (event.kind == EventKind.deletion ||
        event.kind == EventKind.nip29DeleteEvent)
      for (final tag in event.tags)
        if (tag.length >= 2 && tag[0] == 'e') tag[1],
};
