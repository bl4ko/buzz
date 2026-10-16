import 'package:buzz/features/channels/channel_tabs/canvas_doc.dart';
import 'package:buzz/features/channels/channel_tabs/canvas_doc_provider.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nostr/nostr.dart' as nostr;

import '../message_pins/pins_fixtures.dart';

void main() {
  test('canvas save reports a conflict and saves when forced', () async {
    final keys = nostr.Keys.generate();
    final relay = PinsRelay(
      stored: [
        NostrEvent(
          id: '2',
          pubkey: 'b' * 64,
          createdAt: 20,
          kind: EventKind.channelCanvasDoc,
          tags: [
            ['d', '$pinsChannelId:notes'],
            ['h', pinsChannelId],
          ],
          content: 'theirs',
          sig: '',
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        relayConfigProvider.overrideWith(() => PinsConfig(keys.nsec)),
        relaySessionProvider.overrideWith(() => relay),
      ],
    );
    addTearDown(container.dispose);
    final key = (pinsChannelId, 'notes');
    final doc = container.listen(canvasDocProvider(key), (_, _) {});
    await pumpEventQueue();
    expect(doc.read()!.eventId, '2');
    final notifier = container.read(canvasDocProvider(key).notifier);
    expect(await notifier.save('mine', '1'), CanvasSaveResult.conflict);
    expect(relay.published, isEmpty);
    expect(
      await notifier.save('mine', '1', force: true),
      CanvasSaveResult.saved,
    );
    expect(relay.published.single.tags, [
      ['d', '$pinsChannelId:notes'],
      ['h', pinsChannelId],
    ]);
    expect(relay.published.single.createdAt, greaterThan(20));
    await expectLater(
      notifier.save('x' * 65537, doc.read()!.eventId),
      throwsA(isA<ArgumentError>()),
    );
  });
}
