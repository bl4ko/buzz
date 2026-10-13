import 'package:buzz/features/channels/channel.dart';
import 'package:buzz/features/channels/channel_identity_names_provider.dart';
import 'package:buzz/features/channels/message_pins/message_pins_provider.dart';
import 'package:buzz/features/channels/message_pins/pinned_messages_page.dart';
import 'package:buzz/shared/identity_names/identity_names.dart';
import 'package:buzz/shared/profile/user_profile.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nostr/nostr.dart' as nostr;

import '../../../helpers/widget_helpers.dart';
import 'pins_fixtures.dart';

void main() {
  testWidgets('lists live pins newest first and unpins from a row', (
    tester,
  ) async {
    final keys = nostr.Keys.generate();
    final relay = PinsRelay(
      stored: [
        pinEvent('p1', target: 'older', createdAt: 10),
        pinEvent('p2', target: 'newer', createdAt: 20),
        pinEvent('p3', target: 'deleted', createdAt: 30),
        pinEvent('p4', target: 'missing', createdAt: 40),
      ],
      targets: [
        messageEvent('older', content: 'Older pinned message'),
        messageEvent('newer', content: 'Newer pinned message'),
        messageEvent('deleted', content: 'Deleted pinned message'),
        messageEvent(
          'foreign',
          content: 'Other channel message',
          channelId: 'channel-2',
        ),
      ],
    );
    final channel = Channel(
      id: pinsChannelId,
      name: 'general',
      channelType: 'stream',
      visibility: 'open',
      description: '',
      createdBy: 'alice',
      createdAt: DateTime.utc(2026),
      memberCount: 1,
      isMember: true,
    );

    await tester.pumpWidget(
      WidgetHelpers.testable(
        overrides: [
          relayConfigProvider.overrideWith(() => PinsConfig(keys.nsec)),
          relaySessionProvider.overrideWith(() => relay),
          channelDeletedEventIdsProvider(
            pinsChannelId,
          ).overrideWith((ref) => {'deleted'}),
          channelIdentityNamesProvider(pinsChannelId).overrideWith(
            (ref) => const IdentityNameSources(
              profiles: {
                'alice': UserProfile(pubkey: 'alice', displayName: 'Alice'),
              },
            ).scope(['alice']),
          ),
        ],
        child: PinnedMessagesPage(channel: channel),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Pinned messages'), findsOneWidget);
    expect(find.text('Older pinned message'), findsOneWidget);
    expect(find.text('Newer pinned message'), findsOneWidget);
    expect(find.text('Deleted pinned message'), findsNothing);
    expect(find.text('Alice'), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('Newer pinned message')).dy,
      lessThan(tester.getTopLeft(find.text('Older pinned message')).dy),
    );

    await tester.tap(find.byKey(const ValueKey('unpin-message-newer')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final published = relay.published.single;
    expect(published.kind, EventKind.streamMessagePinned);
    expect(published.tags, [
      ['h', pinsChannelId],
      ['e', 'newer'],
      ['status', 'unpinned'],
    ]);
    expect(find.text('Newer pinned message'), findsNothing);
    expect(find.text('Older pinned message'), findsOneWidget);

    relay.live!(
      pinEvent('p5', target: 'older', createdAt: 50, status: 'unpinned'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Older pinned message'), findsNothing);
    expect(
      find.text('No pinned messages yet. Pin a message from its menu.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
