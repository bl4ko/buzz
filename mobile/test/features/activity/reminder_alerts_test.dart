import 'package:buzz/features/activity/reminder_alerts.dart';
import 'package:buzz/features/activity/reminders_provider.dart';
import 'package:buzz/shared/community/community.dart';
import 'package:buzz/shared/community/community_provider.dart';
import 'package:buzz/shared/profile/user_cache_provider.dart';
import 'package:buzz/shared/profile/user_profile.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _author =
    'aa00000000000000000000000000000000000000000000000000000000000001';

Reminder _reminder(
  String id, {
  int? notBefore,
  String status = 'pending',
  ReminderTarget? target = const ReminderTarget(
    eventId: 'message-1',
    channelId: 'channel-1',
    preview: 'Ship the build',
    authorPubkey: _author,
  ),
  String? note,
}) => Reminder(
  id: id,
  notBefore: notBefore,
  status: status,
  target: target,
  note: note,
  createdAt: 1,
  eventId: 'event-$id',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('upcomingReminders', () {
    const now = 1000;

    test('keeps only pending reminders due after now', () {
      final cases = [
        (status: 'pending', notBefore: now + 1, kept: true),
        (status: 'pending', notBefore: now, kept: false),
        (status: 'pending', notBefore: now - 1, kept: false),
        (status: 'pending', notBefore: null, kept: false),
        (status: 'done', notBefore: now + 1, kept: false),
        (status: 'done', notBefore: null, kept: false),
        (status: 'cancelled', notBefore: now + 1, kept: false),
        (status: 'cancelled', notBefore: null, kept: false),
      ];
      for (final c in cases) {
        final result = upcomingReminders([
          _reminder('r', status: c.status, notBefore: c.notBefore),
        ], nowUnixSeconds: now);
        expect(result.length, c.kept ? 1 : 0, reason: '$c');
      }
    });

    test('sorts soonest first with a stable id tie-break', () {
      final result = upcomingReminders([
        _reminder('c', notBefore: now + 30),
        _reminder('b', notBefore: now + 10),
        _reminder('a', notBefore: now + 10),
        _reminder('d', notBefore: now + 20),
      ], nowUnixSeconds: now);
      expect(result.map((r) => r.id), ['a', 'b', 'd', 'c']);
    });

    test('caps at the soonest reminderAlertLimit reminders', () {
      final result = upcomingReminders([
        for (var i = 80; i > 0; i--) _reminder('r$i', notBefore: now + i),
      ], nowUnixSeconds: now);
      expect(reminderAlertLimit, 50);
      expect(result, hasLength(50));
      expect(result.first.id, 'r1');
      expect(result.last.id, 'r50');
    });
  });

  group('reminderAlertFor', () {
    test('uses the sender name and preview with a message target', () {
      final alert = reminderAlertFor(
        _reminder('r1', notBefore: 5000),
        communityId: 'community-1',
        senderName: ' Ana ',
      );
      expect(alert.toMap(), {
        'id': 'r1',
        'fireAt': 5000,
        'title': 'Reminder',
        'body': 'Ana: Ship the build',
        'communityId': 'community-1',
        'channelId': 'channel-1',
        'messageId': 'message-1',
      });
    });

    test('falls back to preview only, then to the generic text', () {
      expect(
        reminderAlertFor(
          _reminder('r1', notBefore: 5000),
          communityId: 'c',
        ).body,
        'Ship the build',
      );
      expect(
        reminderAlertFor(
          _reminder(
            'r1',
            notBefore: 5000,
            target: const ReminderTarget(
              eventId: 'm',
              channelId: 'ch',
              preview: '  ',
              authorPubkey: _author,
            ),
          ),
          communityId: 'c',
          senderName: 'Ana',
        ).body,
        reminderAlertFallbackBody,
      );
    });

    test('a note-only reminder shows its note and has no target', () {
      final alert = reminderAlertFor(
        _reminder('r1', notBefore: 5000, target: null, note: 'Water plants'),
        communityId: 'c',
        senderName: 'Ana',
      );
      expect(alert.body, 'Water plants');
      expect(alert.channelId, isNull);
      expect(alert.messageId, isNull);
    });

    test('flattens whitespace and shortens long previews', () {
      final alert = reminderAlertFor(
        _reminder(
          'r1',
          notBefore: 5000,
          target: ReminderTarget(
            eventId: 'm',
            channelId: 'ch',
            preview: 'line one\n\nline two ${'x' * 300}',
            authorPubkey: _author,
          ),
        ),
        communityId: 'c',
      );
      expect(alert.body, startsWith('line one line two x'));
      expect(alert.body.length, 120);
      expect(alert.body, endsWith('…'));
    });
  });

  test(
    'ReminderAlertChannel sends sync and clear over buzz/reminder_alerts',
    () async {
      const channel = MethodChannel('buzz/reminder_alerts');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      const alert = ReminderAlert(
        id: 'r1',
        fireAt: 5000,
        title: 'Reminder',
        body: 'Ship',
        communityId: 'c',
      );
      await const ReminderAlertChannel().sync([alert]);
      await const ReminderAlertChannel().clear();
      expect(calls.map((c) => c.method), ['sync', 'clear']);
      expect(calls.first.arguments, [alert.toMap()]);
    },
  );

  group('reminderAlertSyncProvider', () {
    late _Fixture fixture;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      fixture = _Fixture();
    });

    tearDown(() {
      fixture.container.dispose();
      debugDefaultTargetPlatformOverride = null;
    });

    test(
      'syncs upcoming reminders on load and every change, without repeats',
      () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        fixture.reminders = [
          _reminder('later', notBefore: now + 7200),
          _reminder('soon', notBefore: now + 3600),
          _reminder('done', notBefore: now + 60, status: 'done'),
          _reminder('archived', notBefore: now + 60, status: 'cancelled'),
          _reminder('past', notBefore: now - 60),
        ];
        await fixture.start();

        expect(fixture.channel.calls, hasLength(1));
        final first = fixture.channel.calls.single as List<ReminderAlert>;
        expect(first.map((a) => a.id), ['soon', 'later']);
        expect(first.first.body, 'Ana: Ship the build');
        expect(first.first.communityId, 'community-1');

        fixture.setReminders([_reminder('later', notBefore: now + 7200)]);
        await pumpEventQueue();
        expect(fixture.channel.calls, hasLength(2));
        expect(
          (fixture.channel.calls.last as List<ReminderAlert>).map((a) => a.id),
          ['later'],
        );

        fixture.setReminders([_reminder('later', notBefore: now + 7200)]);
        await pumpEventQueue();
        expect(fixture.channel.calls, hasLength(2));

        fixture.subscription.close();
        await pumpEventQueue();
        expect(fixture.channel.calls, hasLength(3));
        expect(fixture.channel.calls.last, 'clear');
      },
    );

    test('clears alerts on account switch and on sign-out', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      fixture.reminders = [_reminder('r1', notBefore: now + 3600)];
      await fixture.start();
      expect(fixture.channel.calls, hasLength(1));

      fixture.container.read(_accountProvider.notifier).set('b' * 64);
      await pumpEventQueue();
      expect(fixture.channel.calls[1], 'clear');

      fixture.container.read(_accountProvider.notifier).set(null);
      await pumpEventQueue();
      expect(fixture.channel.calls.last, 'clear');
      final clears = fixture.channel.calls.where((c) => c == 'clear').length;

      fixture.subscription.close();
      await pumpEventQueue();
      expect(fixture.channel.calls.where((c) => c == 'clear').length, clears);
    });

    test('does nothing outside iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      fixture.reminders = [_reminder('r1', notBefore: now + 3600)];
      await fixture.start();
      fixture.subscription.close();
      await pumpEventQueue();
      expect(fixture.channel.calls, isEmpty);
    });
  });
}

class _Fixture {
  final channel = _RecordingChannel();
  List<Reminder> reminders = const [];
  late final ProviderContainer container = ProviderContainer(
    overrides: [
      reminderAlertChannelProvider.overrideWithValue(channel),
      remindersProvider.overrideWith(() => _Reminders(reminders)),
      activeCommunityProvider.overrideWith(
        (ref) async => Community(
          id: 'community-1',
          name: 'Test',
          relayUrl: 'wss://relay.example',
          addedAt: DateTime(2026),
        ),
      ),
      myPubkeyProvider.overrideWith((ref) => ref.watch(_accountProvider)),
      userCacheProvider.overrideWith(
        () => _UserCache({
          _author: const UserProfile(pubkey: _author, displayName: 'Ana'),
        }),
      ),
    ],
  );
  late final ProviderSubscription<void> subscription;

  Future<void> start() async {
    await container.read(activeCommunityProvider.future);
    subscription = container.listen(reminderAlertSyncProvider, (_, _) {});
    await container.read(remindersProvider.future);
    await pumpEventQueue();
  }

  void setReminders(List<Reminder> next) {
    container.read(remindersProvider.notifier).state = AsyncData(next);
  }
}

class _RecordingChannel extends ReminderAlertChannel {
  final calls = <Object>[];

  @override
  Future<void> sync(List<ReminderAlert> alerts) async => calls.add(alerts);

  @override
  Future<void> clear() async => calls.add('clear');
}

class _Reminders extends RemindersNotifier {
  _Reminders(this._initial);

  final List<Reminder> _initial;

  @override
  Future<List<Reminder>> build() async => _initial;
}

final _accountProvider = NotifierProvider<_Account, String?>(_Account.new);

class _Account extends Notifier<String?> {
  @override
  String? build() => 'a' * 64;

  void set(String? value) => state = value;
}

class _UserCache extends UserCacheNotifier {
  _UserCache(this._users);

  final Map<String, UserProfile> _users;

  @override
  Map<String, UserProfile> build() => _users;
}
