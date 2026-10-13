import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/relay/relay.dart';
import '../channel_management_provider.dart';
import '../channel_messages_provider.dart';
import '../timeline_message.dart';
import 'message_pins.dart';

export 'message_pins.dart';

const pinnableMessageKinds = [
  EventKind.streamMessage,
  EventKind.streamMessageV2,
];

const _pinSubscriptionLimit = 500;

class ChannelMessagePinsNotifier extends Notifier<ChannelMessagePins> {
  ChannelMessagePinsNotifier(this.channelId);

  final String channelId;
  (String, String?)? _scope;
  ChannelMessagePins _pins = const ChannelMessagePins();

  @override
  ChannelMessagePins build() {
    final config = ref.watch(relayConfigProvider);
    final connected = ref.watch(
      relaySessionProvider.select(
        (session) => session.status == SessionStatus.connected,
      ),
    );
    final scope = (config.baseUrl, config.nsec);
    if (scope != _scope) {
      _scope = scope;
      _pins = const ChannelMessagePins();
    }
    if (connected) {
      var disposed = false;
      void Function()? unsubscribe;
      ref.onDispose(() {
        disposed = true;
        unsubscribe?.call();
      });
      unawaited(
        ref
            .read(relaySessionProvider.notifier)
            .subscribe(
              NostrFilter(
                kinds: const [EventKind.streamMessagePinned],
                tags: {
                  '#h': [channelId],
                },
                limit: _pinSubscriptionLimit,
              ),
              (event) {
                if (!disposed) receive(event);
              },
            )
            .then(
              (cancel) => disposed ? cancel() : unsubscribe = cancel,
              onError: (Object _) {},
            ),
      );
    }
    return _pins;
  }

  void receive(NostrEvent event) {
    final pin = MessagePinEvent.fromEvent(event, channelId: channelId);
    if (pin == null) return;
    final next = _pins.apply(pin);
    if (identical(next, _pins)) return;
    _pins = next;
    state = next;
  }

  Future<void> setPinned(String eventId, {required bool pinned}) async {
    NostrEvent? signed;
    await ref
        .read(channelActionsProvider)
        .setMessagePinned(
          channelId: channelId,
          eventId: eventId,
          pinned: pinned,
          createdAt: _pins.nextCreatedAt(
            eventId,
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
          ),
          onSigned: (event) => signed = event,
        );
    final event = signed;
    if (event != null && ref.mounted) receive(event);
  }
}

final channelMessagePinsProvider = NotifierProvider.autoDispose
    .family<ChannelMessagePinsNotifier, ChannelMessagePins, String>(
      ChannelMessagePinsNotifier.new,
    );

final channelDeletedEventIdsProvider = Provider.autoDispose
    .family<Set<String>, String>(
      (ref, channelId) => deletedEventIds(
        ref.watch(channelMessagesProvider(channelId)).value ??
            const <NostrEvent>[],
      ),
    );

final channelPinnedMessagesProvider = Provider.autoDispose
    .family<List<MessagePinEvent>, String>(
      (ref, channelId) => ref
          .watch(channelMessagePinsProvider(channelId))
          .pinned(
            deletedIds: ref.watch(channelDeletedEventIdsProvider(channelId)),
          ),
    );

final pinnedMessageTargetsProvider = FutureProvider.autoDispose
    .family<Map<String, TimelineMessage>, (String, String)>((ref, query) async {
      final (channelId, joinedIds) = query;
      if (joinedIds.isEmpty) return const {};
      final ids = joinedIds.split(',');
      final session = ref.read(relaySessionProvider.notifier);
      final results = await Future.wait([
        session.fetchHistory(
          NostrFilter(ids: ids, kinds: pinnableMessageKinds, limit: ids.length),
        ),
        session.fetchHistory(
          NostrFilter(
            kinds: const [
              EventKind.streamMessageEdit,
              EventKind.deletion,
              EventKind.nip29DeleteEvent,
            ],
            tags: {'#e': ids},
            limit: _pinSubscriptionLimit,
          ),
        ),
      ]);
      final events = [
        for (final event in results[0])
          if (event.getTagValue('h') == channelId) event,
        ...results[1],
      ]..sort((left, right) => left.createdAt.compareTo(right.createdAt));
      return {
        for (final message in formatTimeline(
          events,
          currentPubkey: ref.read(currentPubkeyProvider),
        ))
          if (!message.isSystem) message.id: message,
      };
    });
