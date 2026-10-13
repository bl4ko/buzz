import 'dart:async';
import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/community/community_provider.dart';
import '../../shared/profile/user_cache_provider.dart';
import '../../shared/relay/relay.dart';
import 'reminders_provider.dart';

/// iOS keeps at most 64 pending local notifications per app.
const reminderAlertLimit = 50;
const reminderAlertTitle = 'Reminder';
const reminderAlertFallbackBody = 'You asked to be reminded about a message';
const _previewLength = 120;

@immutable
class ReminderAlert {
  final String id;
  final int fireAt;
  final String title;
  final String body;
  final String communityId;
  final String? channelId;
  final String? messageId;

  const ReminderAlert({
    required this.id,
    required this.fireAt,
    required this.title,
    required this.body,
    required this.communityId,
    this.channelId,
    this.messageId,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'fireAt': fireAt,
    'title': title,
    'body': body,
    'communityId': communityId,
    'channelId': channelId,
    'messageId': messageId,
  };
}

List<Reminder> upcomingReminders(
  Iterable<Reminder> reminders, {
  required int nowUnixSeconds,
  int limit = reminderAlertLimit,
}) {
  final upcoming = [
    for (final reminder in reminders)
      if (reminder.status == 'pending' &&
          reminder.notBefore != null &&
          reminder.notBefore! > nowUnixSeconds)
        reminder,
  ];
  upcoming.sort((a, b) {
    final byTime = a.notBefore!.compareTo(b.notBefore!);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
  return upcoming.take(limit).toList();
}

ReminderAlert reminderAlertFor(
  Reminder reminder, {
  required String communityId,
  String? senderName,
}) {
  final target = reminder.target;
  final preview = _shorten(target?.preview ?? reminder.note ?? '');
  final name = senderName?.trim() ?? '';
  final body = preview.isEmpty
      ? reminderAlertFallbackBody
      : target != null && name.isNotEmpty
      ? '$name: $preview'
      : preview;
  return ReminderAlert(
    id: reminder.id,
    fireAt: reminder.notBefore!,
    title: reminderAlertTitle,
    body: body,
    communityId: communityId,
    channelId: target?.channelId,
    messageId: target?.eventId,
  );
}

String _shorten(String text) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final characters = flat.characters;
  if (characters.length <= _previewLength) return flat;
  return '${characters.take(_previewLength - 1).toString().trimRight()}…';
}

class ReminderAlertChannel {
  static const _channel = MethodChannel('buzz/reminder_alerts');

  const ReminderAlertChannel();

  Future<void> sync(List<ReminderAlert> alerts) =>
      _invoke('sync', [for (final alert in alerts) alert.toMap()]);

  Future<void> clear() => _invoke('clear');

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (error) {
      debugPrint('reminder-alerts: $method failed: ${error.message}');
    } on MissingPluginException {
      return;
    }
  }
}

final reminderAlertChannelProvider = Provider<ReminderAlertChannel>(
  (ref) => const ReminderAlertChannel(),
);

final reminderAlertSyncProvider = Provider.autoDispose<void>((ref) {
  if (defaultTargetPlatform != TargetPlatform.iOS) return;
  final channel = ref.watch(reminderAlertChannelProvider);
  final communityId = ref.watch(
    activeCommunityProvider.select((community) => community.value?.id),
  );
  final account = ref.watch(myPubkeyProvider);
  if (communityId == null || account == null) return;

  var disposed = false;
  String? lastSent;
  ref.onDispose(() {
    disposed = true;
    unawaited(channel.clear());
  });

  void sync() {
    if (disposed) return;
    if (ref.read(remindersProvider) case AsyncData(:final value)) {
      final profiles = ref.read(userCacheProvider);
      final alerts = [
        for (final reminder in upcomingReminders(
          value,
          nowUnixSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ))
          reminderAlertFor(
            reminder,
            communityId: communityId,
            senderName: switch (reminder.target?.authorPubkey) {
              final pubkey? => profiles[pubkey.toLowerCase()]?.displayName,
              null => null,
            },
          ),
      ];
      final encoded = jsonEncode([for (final alert in alerts) alert.toMap()]);
      if (encoded == lastSent) return;
      lastSent = encoded;
      unawaited(channel.sync(alerts));
    }
  }

  ref.listen(remindersProvider, (_, _) => sync(), fireImmediately: true);
  ref.listen(userCacheProvider, (_, _) => sync());
});
