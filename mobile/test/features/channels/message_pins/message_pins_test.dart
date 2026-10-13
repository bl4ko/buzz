import 'package:buzz/features/channels/message_pins/message_pins_provider.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nostr/nostr.dart' as nostr;

import 'pins_fixtures.dart';

List<List<T>> _permutations<T>(List<T> items) {
  if (items.length <= 1) return [items];
  return [
    for (var i = 0; i < items.length; i++)
      for (final rest in _permutations([
        ...items.sublist(0, i),
        ...items.sublist(i + 1),
      ]))
        [items[i], ...rest],
  ];
}

void main() {
  group('reduceMessagePins', () {
    final cases = <({String name, List<NostrEvent> events, bool pinned})>[
      (
        name: 'single pin',
        events: [pinEvent('b', target: 'm', createdAt: 10)],
        pinned: true,
      ),
      (
        name: 'newer unpin wins',
        events: [
          pinEvent('b', target: 'm', createdAt: 10),
          pinEvent('c', target: 'm', createdAt: 11, status: 'unpinned'),
        ],
        pinned: false,
      ),
      (
        name: 'newer repin wins',
        events: [
          pinEvent('b', target: 'm', createdAt: 10),
          pinEvent('c', target: 'm', createdAt: 11, status: 'unpinned'),
          pinEvent('d', target: 'm', createdAt: 12),
        ],
        pinned: true,
      ),
      (
        name: 'tie keeps lower id pin',
        events: [
          pinEvent('a', target: 'm', createdAt: 10),
          pinEvent('b', target: 'm', createdAt: 10, status: 'unpinned'),
        ],
        pinned: true,
      ),
      (
        name: 'tie keeps lower id unpin',
        events: [
          pinEvent('b', target: 'm', createdAt: 10),
          pinEvent('a', target: 'm', createdAt: 10, status: 'unpinned'),
        ],
        pinned: false,
      ),
      (
        name: 'older event never overrides',
        events: [
          pinEvent('z', target: 'm', createdAt: 20, status: 'unpinned'),
          pinEvent('a', target: 'm', createdAt: 5),
        ],
        pinned: false,
      ),
    ];
    for (final testCase in cases) {
      test('${testCase.name} in every arrival order', () {
        for (final order in _permutations(testCase.events)) {
          final pins = reduceMessagePins(order, channelId: pinsChannelId);
          expect(pins.isPinned('m'), testCase.pinned, reason: '$order');
        }
      });
    }

    test('ignores malformed and foreign pin events', () {
      final pins = reduceMessagePins([
        pinEvent('a', target: 'm1', createdAt: 1, channelId: 'other'),
        pinEvent('b', target: 'm2', createdAt: 1, status: 'maybe'),
        pinEvent(
          'c',
          target: 'm3',
          createdAt: 1,
          tags: const [
            ['h', pinsChannelId],
            ['e', 'm3'],
            ['e', 'm4'],
            ['status', 'pinned'],
          ],
        ),
        pinEvent(
          'd',
          target: 'm5',
          createdAt: 1,
          tags: const [
            ['h', pinsChannelId],
            ['e', 'm5'],
          ],
        ),
        pinEvent(
          'e',
          target: 'm6',
          createdAt: 1,
          kind: EventKind.streamMessageEdit,
        ),
      ], channelId: pinsChannelId);
      expect(pins.latestByTarget, isEmpty);
    });

    test('lists newest pin first and skips deleted targets', () {
      final pins = reduceMessagePins([
        pinEvent('p1', target: 'old', createdAt: 1),
        pinEvent('p2', target: 'new', createdAt: 3),
        pinEvent('p3', target: 'deleted', createdAt: 4),
        pinEvent('p4', target: 'gone', createdAt: 2),
        pinEvent('p5', target: 'gone', createdAt: 5, status: 'unpinned'),
      ], channelId: pinsChannelId);
      final deleted = deletedEventIds([
        NostrEvent(
          id: 'del',
          pubkey: 'alice',
          createdAt: 6,
          kind: EventKind.nip29DeleteEvent,
          tags: const [
            ['h', pinsChannelId],
            ['e', 'deleted'],
          ],
          content: '',
          sig: '',
        ),
      ]);
      expect(pins.pinned(deletedIds: deleted).map((pin) => pin.targetId), [
        'new',
        'old',
      ]);
    });

    test('next pin time stays ahead of the current state', () {
      final pins = reduceMessagePins([
        pinEvent('p', target: 'm', createdAt: 500),
      ], channelId: pinsChannelId);
      expect(pins.nextCreatedAt('m', 100), 501);
      expect(pins.nextCreatedAt('m', 900), 900);
      expect(pins.nextCreatedAt('other', 100), 100);
    });
  });

  group('channelMessagePinsProvider', () {
    late nostr.Keys keys;
    late PinsRelay relay;
    late ProviderContainer container;

    setUp(() {
      keys = nostr.Keys.generate();
      relay = PinsRelay(
        stored: [
          pinEvent('p1', target: 'm1', createdAt: 10),
          pinEvent('p2', target: 'm2', createdAt: 20),
        ],
      );
      container = ProviderContainer(
        overrides: [
          relayConfigProvider.overrideWith(() => PinsConfig(keys.nsec)),
          relaySessionProvider.overrideWith(() => relay),
          channelDeletedEventIdsProvider(
            pinsChannelId,
          ).overrideWith((ref) => {'m2'}),
        ],
      );
      addTearDown(container.dispose);
    });

    test('loads stored pins and follows live events', () async {
      final pins = container.listen(
        channelMessagePinsProvider(pinsChannelId),
        (_, _) {},
      );
      final listed = container.listen(
        channelPinnedMessagesProvider(pinsChannelId),
        (_, _) {},
      );
      await pumpEventQueue();

      final filter = relay.subscriptions.single;
      expect(filter.kinds, [EventKind.streamMessagePinned]);
      expect(filter.tags, {
        '#h': [pinsChannelId],
      });
      expect(pins.read().isPinned('m1'), isTrue);
      expect(listed.read().map((pin) => pin.targetId), ['m1']);

      relay.live!(
        pinEvent('p3', target: 'm1', createdAt: 30, status: 'unpinned'),
      );
      expect(pins.read().isPinned('m1'), isFalse);
      expect(listed.read(), isEmpty);

      relay.live!(pinEvent('p0', target: 'm1', createdAt: 29));
      expect(pins.read().isPinned('m1'), isFalse);
    });

    test('publishes a signed pin event and applies it locally', () async {
      final pins = container.listen(
        channelMessagePinsProvider(pinsChannelId),
        (_, _) {},
      );
      await pumpEventQueue();
      relay.live!(
        pinEvent(
          'future',
          target: 'm3',
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 100,
        ),
      );

      await container
          .read(channelMessagePinsProvider(pinsChannelId).notifier)
          .setPinned('m3', pinned: false);

      final published = relay.published.single;
      expect(published.kind, EventKind.streamMessagePinned);
      expect(published.pubkey, keys.public);
      expect(published.content, '');
      expect(published.tags, [
        ['h', pinsChannelId],
        ['e', 'm3'],
        ['status', 'unpinned'],
      ]);
      expect(published.createdAt, pins.read().latestByTarget['m3']!.createdAt);
      expect(pins.read().latestByTarget['m3']!.id, published.id);
      expect(pins.read().isPinned('m3'), isFalse);
    });
  });
}
