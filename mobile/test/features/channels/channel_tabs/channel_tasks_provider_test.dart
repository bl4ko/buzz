import 'package:buzz/features/channels/channel_tabs/channel_tasks_provider.dart';
import 'package:buzz/features/channels/channel_tabs/thread_status.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nostr/nostr.dart' as nostr;

import '../message_pins/pins_fixtures.dart';
import 'thread_status_test.dart' as fixtures;

class TasksRelay extends PinsRelay {
  TasksRelay({super.stored});

  final callbacks = <void Function(NostrEvent)>[];

  @override
  Future<void Function()> subscribe(
    NostrFilter filter,
    void Function(NostrEvent) onEvent, {
    void Function(String message)? onClosed,
  }) {
    callbacks.add(onEvent);
    return super.subscribe(filter, onEvent, onClosed: onClosed);
  }
}

void main() {
  late nostr.Keys keys;
  late TasksRelay relay;
  late ProviderContainer container;

  setUp(() {
    keys = nostr.Keys.generate();
    relay = TasksRelay(
      stored: [
        fixtures.status(
          'w',
          'awaiting_owner',
          10,
          askText: 'Merge PR 7?',
          channel: pinsChannelId,
        ),
      ],
    );
    container = ProviderContainer(
      overrides: [
        relayConfigProvider.overrideWith(() => PinsConfig(keys.nsec)),
        relaySessionProvider.overrideWith(() => relay),
      ],
    );
    addTearDown(container.dispose);
  });

  test(
    'subscribes, counts tasks that need the owner, and follows live updates',
    () async {
      final tasks = container.listen(
        channelTasksProvider(pinsChannelId),
        (_, _) {},
      );
      await pumpEventQueue();
      expect(relay.subscriptions.first.kinds, [EventKind.threadStatus]);
      expect(relay.subscriptions.first.tags, {
        '#h': [pinsChannelId],
      });
      expect(tasks.read().awaitingCount, 1);
      relay.callbacks.first(
        fixtures.status('p', 'in_progress', 20, channel: pinsChannelId),
      );
      expect(tasks.read().awaitingCount, 0);
    },
  );

  test(
    'markDone publishes a signed owner status with the same title',
    () async {
      final tasks = container.listen(
        channelTasksProvider(pinsChannelId),
        (_, _) {},
      );
      await pumpEventQueue();
      await container
          .read(channelTasksProvider(pinsChannelId).notifier)
          .markDone(tasks.read().tasks.single);
      final published = relay.published.single;
      expect(published.kind, EventKind.threadStatus);
      expect(published.pubkey, keys.public);
      expect(
        published.tags,
        threadStatusTags(
          rootId: fixtures.root,
          channelId: pinsChannelId,
          status: TaskStatus.done,
          title: 'Rotate keys',
        ),
      );
      expect(published.createdAt, greaterThan(10));
      expect(tasks.read().groups.done.single.eventId, published.id);
    },
  );

  test('owner decisions come from the own reactions on the asks', () async {
    final tasks = container.listen(
      channelTasksProvider(pinsChannelId),
      (_, _) {},
    );
    await pumpEventQueue();
    final filter = relay.subscriptions.firstWhere(
      (f) => f.kinds.contains(EventKind.reaction),
    );
    expect(filter.authors, [keys.public]);
    expect(filter.tags, {
      '#e': [fixtures.ask],
    });
    expect(relay.subscriptions.length, 2);
    expect(tasks.read().decisions, isEmpty);
    NostrEvent reaction(String id, String pubkey, String emoji, int at) =>
        NostrEvent(
          id: id,
          pubkey: pubkey,
          createdAt: at,
          kind: EventKind.reaction,
          tags: [
            ['e', fixtures.ask],
          ],
          content: emoji,
          sig: '',
        );
    relay.live!(reaction('r2', keys.public, '❌', 12));
    expect(tasks.read().decisions[fixtures.ask], OwnerDecision.deny);
    relay.live!(reaction('r1', keys.public, '✅', 11));
    relay.live!(reaction('r3', 'f' * 64, '❌', 1));
    expect(tasks.read().decisions[fixtures.ask], OwnerDecision.approve);
    expect(tasks.read().awaitingCount, 1);
  });
}
