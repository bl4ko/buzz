import 'package:buzz/features/channels/channel_tabs/channel_tasks_provider.dart';
import 'package:buzz/features/channels/channel_tabs/thread_status.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nostr/nostr.dart' as nostr;

import '../message_pins/pins_fixtures.dart';
import 'thread_status_test.dart' as fixtures;

void main() {
  late nostr.Keys keys;
  late PinsRelay relay;
  late ProviderContainer container;

  setUp(() {
    keys = nostr.Keys.generate();
    relay = PinsRelay(
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
      expect(relay.subscriptions.single.kinds, [EventKind.threadStatus]);
      expect(relay.subscriptions.single.tags, {
        '#h': [pinsChannelId],
      });
      expect(tasks.read().awaitingCount, 1);
      relay.live!(
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
}
