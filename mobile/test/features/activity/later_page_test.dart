import 'dart:convert';

import 'package:buzz/features/activity/later_page.dart';
import 'package:buzz/features/activity/reminders_provider.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:buzz/shared/reminders/reminder_service.dart' as service;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nostr/nostr.dart' as nostr;

import '../../helpers/widget_helpers.dart';

void main() {
  testWidgets(
    'shows saved preview and completes, archives and restores across tabs',
    (tester) async {
      final keys = nostr.Keys.generate();
      final crypto = service.ReminderCrypto(keys.nsec, keys.public);
      const target = service.ReminderTarget(
        eventId: 'message-1',
        channelId: 'channel-1',
        preview: 'Saved message with a file and link',
        authorPubkey: 'author-1',
      );
      const note = 'Follow up on this message';
      final relay = _SavedItemsRelay(
        NostrEvent(
          id: 'initial-event',
          pubkey: keys.public,
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          kind: kindEventReminder,
          tags: const [
            ['d', 'saved-item-1'],
          ],
          content: crypto.encrypt(
            service.buildReminderPlaintext(target: target, note: note),
          ),
          sig: '',
        ),
      );
      await tester.pumpWidget(
        WidgetHelpers.testable(
          child: const LaterPage(),
          overrides: [
            relayConfigProvider.overrideWith(
              () => _SavedItemsConfig(keys.nsec),
            ),
            relaySessionProvider.overrideWith(() => relay),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(target.preview), findsOneWidget);
      expect(find.text(note), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Archived'), findsOneWidget);

      for (final tab in ['Completed', 'Archived']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(find.text(target.preview), findsNothing);
      }
      await tester.tap(find.text('In progress'));
      await tester.pumpAndSettle();

      for (final transition in [
        (action: 'Mark complete', tab: 'Completed', status: 'done'),
        (action: 'Archive', tab: 'Archived', status: 'cancelled'),
        (action: 'Move to In progress', tab: 'In progress', status: 'pending'),
      ]) {
        final previous = relay.events.last;
        await tester.tap(find.text(transition.action));
        await tester.pumpAndSettle();
        expect(find.text(target.preview), findsNothing);
        final written = relay.events.last;
        expect(written.kind, kindEventReminder);
        expect(written.tags, [
          ['d', 'saved-item-1'],
        ]);
        expect(written.createdAt, greaterThan(previous.createdAt));
        expect(jsonDecode(crypto.decrypt(written.content)), {
          'target': target.toJson(),
          'note': note,
          'status': transition.status,
        });
        await tester.tap(find.text(transition.tab));
        await tester.pumpAndSettle();
        expect(find.text(target.preview), findsOneWidget);
        expect(find.text(note), findsOneWidget);
        expect(
          find.byKey(const ValueKey('later-item-saved-item-1')),
          findsOneWidget,
        );
      }
      expect(relay.events, hasLength(4));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _SavedItemsConfig extends RelayConfigNotifier {
  final String nsec;
  _SavedItemsConfig(this.nsec);

  @override
  RelayConfig build() =>
      RelayConfig(baseUrl: 'https://relay.example', nsec: nsec);
}

class _SavedItemsRelay extends RelaySessionNotifier {
  final List<NostrEvent> events;
  _SavedItemsRelay(NostrEvent initial) : events = [initial];

  @override
  SessionState build() => const SessionState(status: SessionStatus.connected);

  @override
  Future<List<NostrEvent>> fetchHistory(
    NostrFilter filter, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    expect(filter.kinds, [kindEventReminder]);
    expect(filter.authors, [events.first.pubkey]);
    return List.of(events);
  }

  @override
  Future<NostrEvent> publish(
    NostrEvent event, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    events.add(event);
    return event;
  }
}
