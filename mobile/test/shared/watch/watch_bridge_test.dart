import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:buzz/features/age_gate/age_signal_provider.dart';
import 'package:buzz/features/channels/channel.dart';
import 'package:buzz/features/channels/channel_messages_provider.dart';
import 'package:buzz/features/channels/channels_provider.dart';
import 'package:buzz/features/channels/send_message_provider.dart';
import 'package:buzz/shared/auth/auth.dart';
import 'package:buzz/shared/profile/user_cache_provider.dart';
import 'package:buzz/shared/profile/user_profile.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:buzz/shared/watch/watch_bridge.dart';

final _community = Community(
  id: 'community',
  name: 'Test',
  relayUrl: 'https://relay.example',
  addedAt: DateTime(2026),
);

Channel _channel(String id, {bool member = true}) => Channel(
  id: id,
  name: id,
  channelType: 'stream',
  visibility: 'private',
  description: '',
  createdBy: 'a' * 64,
  createdAt: DateTime(2026),
  memberCount: 1,
  isMember: member,
);

class _Auth extends AuthNotifier {
  @override
  Future<AuthState> build() async =>
      AuthState(status: AuthStatus.authenticated, community: _community);

  void logout() {
    state = const AsyncData(AuthState(status: AuthStatus.unauthenticated));
  }
}

class _Age extends AgeSignalNotifier {
  @override
  AgeSignalState build() => AgeSignalState.allowed;

  void restrict() {
    state = AgeSignalState.restricted;
  }
}

class _Config extends RelayConfigNotifier {
  @override
  RelayConfig build() =>
      const RelayConfig(baseUrl: 'https://relay.example', nsec: null);
}

class _Channels extends ChannelsNotifier {
  @override
  Future<List<Channel>> build() async => [
    _channel('private-other', member: false),
    for (var index = 0; index < 35; index++) _channel('channel-$index'),
  ];
}

class _Profiles extends UserCacheNotifier {
  @override
  Map<String, UserProfile> build() => {};
}

class _Messages extends ChannelMessagesNotifier {
  _Messages(super.channelId);

  @override
  AsyncValue<List<NostrEvent>> build() => AsyncData([
    for (var index = 0; index < 25; index++)
      NostrEvent(
        id: index.toString(),
        pubkey: 'b' * 64,
        createdAt: index,
        kind: EventKind.streamMessage,
        content: '🐝' * 1000,
        tags: [
          ['h', channelId],
        ],
        sig: '',
      ),
    const NostrEvent(
      id: 'deletion',
      pubkey: '',
      createdAt: 26,
      kind: EventKind.deletion,
      content: '',
      tags: [
        ['e', '24'],
      ],
      sig: '',
    ),
    NostrEvent(
      id: 'edit',
      pubkey: 'b' * 64,
      createdAt: 27,
      kind: EventKind.streamMessageEdit,
      content: 'Edited',
      tags: [
        ['e', '23'],
      ],
      sig: '',
    ),
  ]);
}

class _Send extends SendMessage {
  _Send()
    : super(
        signedEventRelay: SignedEventRelay(
          session: RelaySessionNotifier(),
          nsec: null,
        ),
        fetchMembers: (_) async => [],
        readUserCache: () => {},
        addLocalMessage: (_, _) {},
        completeLocalMessage: (_, _) {},
        removeLocalMessage: (_, _) {},
      );

  final sent = <String>[];

  @override
  Future<void> call({
    required String channelId,
    required String content,
    String? parentEventId,
    String? rootEventId,
    List<String>? mentionPubkeys,
    Channel? channel,
    List<List<String>> mediaTags = const [],
  }) async {
    sent.add(content);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'watch uses current member channels and phone send; no identity export',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final states = <Object?>[];
      messenger.setMockMethodCallHandler(watchChannel, (call) async {
        states.add(call.arguments);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(watchChannel, null));
      final auth = _Auth();
      final age = _Age();
      final send = _Send();
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => auth),
          ageSignalProvider.overrideWith(() => age),
          relayConfigProvider.overrideWith(_Config.new),
          myPubkeyProvider.overrideWithValue('a' * 64),
          channelsProvider.overrideWith(_Channels.new),
          channelMessagesProvider(
            'channel-0',
          ).overrideWith(() => _Messages('channel-0')),
          userCacheProvider.overrideWith(_Profiles.new),
          sendMessageProvider.overrideWithValue(send),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authProvider.future);
      container.read(watchBridgeProvider);
      await Future<void>.delayed(Duration.zero);

      Future<Map<Object?, Object?>> request(Map<String, Object?> args) async {
        final result = Completer<Map<Object?, Object?>>();
        await messenger.handlePlatformMessage(
          watchChannel.name,
          watchChannel.codec.encodeMethodCall(MethodCall('request', args)),
          (reply) =>
              result.complete(watchChannel.codec.decodeEnvelope(reply!) as Map),
        );
        return result.future;
      }

      final listing = await request({'action': 'channels'});
      final scope = listing['scope'];
      final channels = listing['channels'] as List;
      expect(channels, hasLength(30));
      expect(
        channels.any((channel) => (channel as Map)['id'] == 'private-other'),
        false,
      );
      expect(
        (await request({
          'action': 'send',
          'scope': 'old',
          'channelId': 'channel-0',
          'text': 'hello',
        }))['error'],
        isNotNull,
      );
      expect(
        (await request({
          'action': 'send',
          'scope': scope,
          'channelId': 'private-other',
          'text': 'hello',
        }))['error'],
        isNotNull,
      );
      expect(
        (await request({
          'action': 'send',
          'scope': scope,
          'channelId': 'channel-0',
          'text': 'x' * 2001,
        }))['error'],
        isNotNull,
      );
      expect(
        (await request({
          'action': 'send',
          'scope': scope,
          'channelId': 'channel-0',
          'text': ' hello ',
        }))['sent'],
        true,
      );
      expect(send.sent, ['hello']);
      final history = await request({
        'action': 'messages',
        'scope': scope,
        'channelId': 'channel-0',
      });
      final messages = history['messages'] as List;
      expect(messages, hasLength(20));
      expect(messages.any((message) => (message as Map)['id'] == '24'), false);
      expect((messages.first as Map)['text'], '🐝' * 300);
      expect((messages.last as Map)['text'], 'Edited');
      expect(history.keys, unorderedEquals(['scope', 'messages']));
      age.restrict();
      await Future<void>.delayed(Duration.zero);
      expect((await request({'action': 'channels'}))['error'], isNotNull);
      auth.logout();
      await Future<void>.delayed(Duration.zero);
      expect((states.last as Map)['available'], false);
      expect((states.last as Map)['scope'], '');
      expect(send.sent, ['hello']);
    },
  );
}
