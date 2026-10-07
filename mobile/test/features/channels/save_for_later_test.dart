import 'dart:async';
import 'dart:convert';

import 'package:buzz/features/activity/reminders_provider.dart';
import 'package:buzz/features/channels/message_actions.dart';
import 'package:buzz/features/channels/timeline_message.dart';
import 'package:buzz/shared/read_state/read_state_provider.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:buzz/shared/reminders/reminder_service.dart' as service;
import 'package:buzz/shared/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nostr/nostr.dart' as nostr;
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/widget_helpers.dart';

void main() {
  for (final rejectFirst in [false, true]) {
    testWidgets(
      rejectFirst
          ? 'a rejected Save for later releases the pending guard for retry'
          : 'concurrent Save for later selections publish only one saved event',
      (tester) async {
        final keys = nostr.Keys.generate();
        final relay = _SaveRelay(keys.public);
        if (!rejectFirst) relay.historyWait = Completer<List<NostrEvent>>();
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final message = TimelineMessage(
          id: rejectFirst ? 'retry-message' : 'concurrent-message',
          pubkey: 'author',
          createdAt: 1000,
          content: 'Save this message',
        );
        await tester.pumpWidget(
          WidgetHelpers.testable(
            child: MessageActionsButton(
              message: message,
              channelId: 'channel-1',
              currentPubkey: keys.public,
              canManageMessage: false,
              isMember: true,
              isArchived: false,
            ),
            overrides: [
              relayConfigProvider.overrideWith(() => _SaveConfig(keys.nsec)),
              relaySessionProvider.overrideWith(() => relay),
              savedPrefsProvider.overrideWithValue(prefs),
              readStateProvider.overrideWith(_InertReadState.new),
            ],
          ),
        );
        await _save(tester, message.id);
        if (!rejectFirst) {
          expect(relay.attempts, isEmpty);
          await _save(tester, message.id);
          expect(relay.attempts, isEmpty);
          relay.historyWait!.complete([]);
          await tester.pumpAndSettle();
          relay.historyWait = null;
        }
        expect(relay.attempts, hasLength(1));
        await _save(tester, message.id);
        expect(relay.attempts, hasLength(1));
        expect(relay.events, isEmpty);

        if (rejectFirst) {
          relay.pending.completeError(StateError('relay rejected save'));
          await tester.pumpAndSettle();
          expect(
            find.text('Could not save for later. Try again.'),
            findsOneWidget,
          );
          await tester.pump(const Duration(seconds: 4));
          await tester.pumpAndSettle();
          relay.pending = Completer<NostrEvent>();
          await _save(tester, message.id);
          expect(relay.attempts, hasLength(2));
        }
        relay.pending.complete(relay.attempts.last);
        await tester.pumpAndSettle();
        expect(relay.events, hasLength(1));
        expect(find.text('Saved for later'), findsOneWidget);
        final event = relay.events.single;
        expect(event.kind, kindEventReminder);
        expect(event.tags, [
          ['d', matches(RegExp(r'^[0-9a-f]{32}$'))],
        ]);
        expect(
          jsonDecode(
            service.ReminderCrypto(
              keys.nsec,
              keys.public,
            ).decrypt(event.content),
          ),
          {
            'status': 'pending',
            'target': {
              'eventId': message.id,
              'channelId': 'channel-1',
              'preview': message.content,
              'authorPubkey': message.pubkey,
            },
          },
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

Future<void> _save(WidgetTester tester, String messageId) async {
  await tester.tap(find.byKey(ValueKey('message-options-$messageId')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save for later'));
  await tester.pumpAndSettle();
}

class _InertReadState extends ReadStateNotifier {
  @override
  ReadStateState build() => const ReadStateState.inert();
}

class _SaveConfig extends RelayConfigNotifier {
  final String nsec;
  _SaveConfig(this.nsec);

  @override
  RelayConfig build() =>
      RelayConfig(baseUrl: 'https://relay.example', nsec: nsec);
}

class _SaveRelay extends RelaySessionNotifier {
  final String pubkey;
  final attempts = <NostrEvent>[];
  final events = <NostrEvent>[];
  Completer<List<NostrEvent>>? historyWait;
  Completer<NostrEvent> pending = Completer<NostrEvent>();
  _SaveRelay(this.pubkey);

  @override
  SessionState build() => const SessionState(status: SessionStatus.connected);

  @override
  Future<List<NostrEvent>> fetchHistory(
    NostrFilter filter, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    expect(filter.kinds, [kindEventReminder]);
    expect(filter.authors, [pubkey]);
    final wait = historyWait;
    if (wait != null) return wait.future;
    return List.of(events);
  }

  @override
  Future<NostrEvent> publish(
    NostrEvent event, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    attempts.add(event);
    final accepted = await pending.future;
    events.add(event);
    return accepted;
  }
}
