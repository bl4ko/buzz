import 'dart:convert';

import 'package:buzz/features/activity/reminders_provider.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:buzz/shared/reminders/reminder_service.dart' as service;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nostr/nostr.dart' as nostr;

void main() {
  test('saved item recovery pages past 200 without duplicates', () async {
    final fixture = _Fixture();
    addTearDown(fixture.container.dispose);
    fixture.relay.events.addAll([
      for (var index = 0; index < 1350; index++) fixture.event(index),
    ]);
    final items = await fixture.container.read(remindersProvider.future);
    expect(items, hasLength(1350));
    expect(items.map((item) => item.id).toSet(), hasLength(1350));
    expect(items.any((item) => item.id == 'item-0'), isTrue);
    expect(fixture.relay.calls.length, greaterThan(1));
  });

  test(
    'dense timestamps widen the page and keep newest replacements',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.container.dispose);
      fixture.relay.events.addAll([
        for (var index = 0; index < 600; index++)
          fixture.event(index, createdAt: 1000),
        for (var index = 0; index < 201; index++)
          fixture.event(index + 600, createdAt: index + 1),
        fixture.event(900, createdAt: 999, dTag: 'item-0', note: 'Old version'),
        fixture.event(
          901,
          createdAt: 1000,
          dTag: 'item-1',
          note: 'Same-time losing version',
        ),
      ]);
      final items = await fixture.container.read(remindersProvider.future);
      expect(items, hasLength(801));
      expect(
        items.singleWhere((item) => item.id == 'item-0').note,
        'Saved item',
      );
      expect(
        items.singleWhere((item) => item.id == 'item-1').eventId,
        '000001',
      );
      expect(fixture.relay.calls.any((filter) => filter.limit == 1000), isTrue);
    },
  );

  test(
    'a saturated timestamp fails without partial results or a loop',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.container.dispose);
      fixture.relay.events.addAll([
        for (var index = 0; index < 1001; index++)
          fixture.event(index, createdAt: 1000),
      ]);
      await expectLater(
        fixture.container.read(remindersProvider.future),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('full relay page shares one timestamp'),
          ),
        ),
      );
      expect(fixture.relay.calls.length, lessThanOrEqualTo(4));
    },
  );

  test('a failed next page cannot return a partial saved list', () async {
    final fixture = _Fixture(failOnCall: 2);
    addTearDown(fixture.container.dispose);
    fixture.relay.events.addAll([
      for (var index = 0; index < 250; index++) fixture.event(index),
    ]);
    await expectLater(
      fixture.container.read(remindersProvider.future),
      throwsA(isA<StateError>()),
    );
  });
}

class _Fixture {
  final nostr.Keys keys = nostr.Keys.generate();
  late final service.ReminderCrypto crypto = service.ReminderCrypto(
    keys.nsec,
    keys.public,
  );
  late final String ciphertext = crypto.encrypt(
    jsonEncode({'status': 'pending', 'note': 'Saved item'}),
  );
  late final _PagedReminderRelay relay;
  late final ProviderContainer container;

  _Fixture({int? failOnCall}) {
    relay = _PagedReminderRelay(keys.public, failOnCall);
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        relayConfigProvider.overrideWith(() => _PagingConfig(keys.nsec)),
        relaySessionProvider.overrideWith(() => relay),
      ],
    );
  }

  NostrEvent event(int index, {int? createdAt, String? dTag, String? note}) =>
      NostrEvent(
        id: '$index'.padLeft(6, '0'),
        pubkey: keys.public,
        createdAt: createdAt ?? index + 1,
        kind: kindEventReminder,
        tags: [
          ['d', dTag ?? 'item-$index'],
        ],
        content: note == null
            ? ciphertext
            : crypto.encrypt(jsonEncode({'status': 'pending', 'note': note})),
        sig: '',
      );
}

class _PagingConfig extends RelayConfigNotifier {
  final String nsec;
  _PagingConfig(this.nsec);

  @override
  RelayConfig build() =>
      RelayConfig(baseUrl: 'https://relay.example', nsec: nsec);
}

class _PagedReminderRelay extends RelaySessionNotifier {
  final String pubkey;
  final int? failOnCall;
  final events = <NostrEvent>[];
  final calls = <NostrFilter>[];
  _PagedReminderRelay(this.pubkey, this.failOnCall);

  @override
  SessionState build() => const SessionState(status: SessionStatus.connected);

  @override
  Future<List<NostrEvent>> fetchHistory(
    NostrFilter filter, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    calls.add(filter);
    expect(filter.authors, [pubkey]);
    expect(filter.kinds, [kindEventReminder]);
    expect(calls.length, lessThanOrEqualTo(30));
    if (calls.length == failOnCall) throw StateError('relay unavailable');
    final page =
        events
            .where(
              (event) =>
                  filter.until == null || event.createdAt <= filter.until!,
            )
            .toList()
          ..sort((a, b) {
            final timestamp = b.createdAt.compareTo(a.createdAt);
            return timestamp != 0 ? timestamp : a.id.compareTo(b.id);
          });
    final limit = filter.limit;
    return page.take(limit > 1000 ? 1000 : limit).toList();
  }
}
