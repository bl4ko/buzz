import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../features/age_gate/age_signal_provider.dart';
import '../../../features/channels/channel.dart';
import '../../../features/channels/channel_messages_provider.dart';
import '../../../features/channels/channels_provider.dart';
import '../../../features/channels/send_message_provider.dart';
import '../../../features/channels/timeline_message.dart';
import '../auth/auth.dart';
import '../profile/user_cache_provider.dart';
import '../relay/relay.dart';

const watchChannel = MethodChannel('buzz/watch');

final watchBridgeProvider = Provider<void>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
  var generation = 0;
  var requests = 0;

  bool available() =>
      ref.read(authProvider).asData?.value.status == AuthStatus.authenticated &&
      ref.read(authProvider).asData?.value.community != null &&
      ref.read(myPubkeyProvider) != null &&
      ref.read(ageSignalProvider) != AgeSignalState.restricted;

  String scope() => available()
      ? '${ref.read(authProvider).asData!.value.community!.id}:${ref.read(myPubkeyProvider)}'
      : '';

  Future<void> publishState() async {
    generation++;
    await watchChannel.invokeMethod<void>('setState', {
      'available': available(),
      'scope': scope(),
    });
  }

  void updateState() {
    unawaited(
      publishState().catchError((Object error) {
        debugPrint('Watch state transfer failed: ${error.runtimeType}');
      }),
    );
  }

  ref.listen(authProvider, (_, _) => updateState());
  ref.listen(ageSignalProvider, (_, _) => updateState());
  ref.listen(relayConfigProvider, (_, _) => updateState());
  updateState();

  Future<Map<String, Object?>> request(MethodCall call) async {
    if (call.method != 'request') throw MissingPluginException();
    if (!available()) {
      return {'error': 'Sign in to Bl4uzz on your iPhone.'};
    }
    if (requests >= 4) return {'error': 'Wait for the current request.'};
    requests++;
    final requestGeneration = generation;
    final requestScope = scope();
    try {
      final args = Map<String, Object?>.from(call.arguments as Map);
      final action = args['action'];
      final channels = await ref.read(channelsProvider.future);
      if (!ref.mounted || requestGeneration != generation || !available()) {
        return {'error': 'The active account changed. Refresh the watch.'};
      }
      final visible =
          channels
              .where((channel) => channel.isMember && !channel.isArchived)
              .where(
                (channel) => channel.channelType == 'stream' || channel.isDm,
              )
              .toList()
            ..sort(
              (a, b) => (b.lastMessageAt ?? b.createdAt).compareTo(
                a.lastMessageAt ?? a.createdAt,
              ),
            );
      if (action == 'channels') {
        return {
          'scope': requestScope,
          'channels': [
            for (final channel in visible.take(30))
              {
                'id': channel.id,
                'name': String.fromCharCodes(
                  channel
                      .displayLabel(currentPubkey: ref.read(myPubkeyProvider))
                      .runes
                      .take(64),
                ),
              },
          ],
        };
      }
      if (args['scope'] != requestScope) {
        return {'error': 'The active account changed. Refresh the watch.'};
      }
      final id = args['channelId'];
      final Channel? channel = visible
          .where((channel) => channel.id == id)
          .firstOrNull;
      if (channel == null) return {'error': 'This channel is not available.'};
      if (action == 'send') {
        final text = args['text'];
        if (text is! String || text.trim().isEmpty || text.length > 2000) {
          return {'error': 'Enter a message with 1 to 2000 characters.'};
        }
        await ref
            .read(sendMessageProvider)
            .call(
              channelId: channel.id,
              channel: channel,
              content: text.trim(),
            );
        return {'sent': true};
      }
      if (action != 'messages') return {'error': 'Unknown watch request.'};
      final messageProvider = channelMessagesProvider(channel.id);
      final notifier = ref.read(messageProvider.notifier);
      if (!notifier.hasLoadedMessages &&
          ref.read(relaySessionProvider).status != SessionStatus.connected) {
        return {
          'error':
              'The iPhone is not connected to the relay. Try again when it is online.',
        };
      }
      final completer = Completer<List<NostrEvent>>();
      final subscription = ref.listen(messageProvider, (_, value) {
        if (completer.isCompleted) return;
        if (value.hasError) {
          completer.completeError(value.error!, value.stackTrace);
        } else if (value.asData case final data?
            when notifier.hasLoadedMessages) {
          completer.complete(data.value);
        }
      }, fireImmediately: true);
      List<NostrEvent> events;
      try {
        events = await completer.future.timeout(const Duration(seconds: 20));
      } finally {
        subscription.close();
      }
      if (!ref.mounted || requestGeneration != generation || !available()) {
        return {'error': 'The active account changed. Refresh the watch.'};
      }
      final profiles = ref.read(userCacheProvider);
      final messages = formatTimeline(
        events,
      ).where((message) => !message.isSystem).toList();
      return {
        'scope': requestScope,
        'messages': [
          for (final message in messages.reversed.take(20).toList().reversed)
            {
              'id': message.id,
              'author': String.fromCharCodes(
                (profiles[message.pubkey]?.label ?? 'Member').runes.take(32),
              ),
              'text': String.fromCharCodes(message.content.runes.take(300)),
            },
        ],
      };
    } catch (_) {
      return {
        'error':
            'The request failed. Open Bl4uzz on your iPhone. '
            'Check the channel before you send again.',
      };
    } finally {
      requests--;
    }
  }

  watchChannel.setMethodCallHandler(request);
  ref.onDispose(() {
    generation++;
    watchChannel.setMethodCallHandler(null);
  });
});
