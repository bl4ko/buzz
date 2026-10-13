import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter_test/flutter_test.dart';

const pinsChannelId = 'channel-1';

NostrEvent pinEvent(
  String id, {
  required String target,
  required int createdAt,
  String status = 'pinned',
  String channelId = pinsChannelId,
  List<List<String>>? tags,
  int kind = EventKind.streamMessagePinned,
}) => NostrEvent(
  id: id,
  pubkey: 'pinner',
  createdAt: createdAt,
  kind: kind,
  tags:
      tags ??
      [
        ['h', channelId],
        ['e', target],
        ['status', status],
      ],
  content: '',
  sig: '',
);

NostrEvent messageEvent(
  String id, {
  required String content,
  int createdAt = 1000,
  String pubkey = 'alice',
  String channelId = pinsChannelId,
}) => NostrEvent(
  id: id,
  pubkey: pubkey,
  createdAt: createdAt,
  kind: EventKind.streamMessage,
  tags: [
    ['h', channelId],
  ],
  content: content,
  sig: '',
);

class PinsConfig extends RelayConfigNotifier {
  PinsConfig(this.nsec);

  final String nsec;

  @override
  RelayConfig build() =>
      RelayConfig(baseUrl: 'https://relay.example', nsec: nsec);
}

class PinsRelay extends RelaySessionNotifier {
  PinsRelay({this.stored = const [], this.targets = const []});

  final List<NostrEvent> stored;
  final List<NostrEvent> targets;
  final published = <NostrEvent>[];
  final subscriptions = <NostrFilter>[];
  void Function(NostrEvent)? live;

  @override
  SessionState build() => const SessionState(status: SessionStatus.connected);

  @override
  Future<void Function()> subscribe(
    NostrFilter filter,
    void Function(NostrEvent) onEvent, {
    void Function(String message)? onClosed,
  }) async {
    subscriptions.add(filter);
    live = onEvent;
    [...stored, ...published].forEach(onEvent);
    return () => live = null;
  }

  @override
  Future<List<NostrEvent>> fetchHistory(
    NostrFilter filter, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final ids = filter.ids;
    if (ids == null) return const [];
    expect(filter.kinds, isNot(contains(EventKind.streamMessagePinned)));
    return [
      for (final event in targets)
        if (ids.contains(event.id)) event,
    ];
  }

  @override
  Future<NostrEvent> publish(
    NostrEvent event, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    published.add(event);
    return event;
  }
}
