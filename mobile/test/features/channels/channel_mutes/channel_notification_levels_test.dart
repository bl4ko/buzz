import 'dart:convert';

import 'package:buzz/features/channels/channel.dart';
import 'package:buzz/features/channels/channel_mutes/channel_mutes_storage.dart';
import 'package:buzz/features/channels/channel_mutes/channel_notification_levels.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('level survives the synced JSON and nothing keeps the mute flag', () {
    final store = ChannelMuteStore(
      channels: {
        'a': ChannelMuteEntry.forLevel(ChannelNotificationLevel.mentions, 1),
        'b': ChannelMuteEntry.forLevel(ChannelNotificationLevel.nothing, 1),
        'c': ChannelMuteEntry.forLevel(null, 1),
        'd': const ChannelMuteEntry(muted: true, updatedAt: 1),
      },
    );
    final decoded = ChannelMuteStore.fromJson(
      jsonDecode(jsonEncode(store.toJson())) as Map<String, dynamic>,
    );
    expect(decoded.channels['b']!.muted, isTrue);
    expect(explicitChannelLevels(decoded), {
      'a': ChannelNotificationLevel.mentions,
      'b': ChannelNotificationLevel.nothing,
      'd': ChannelNotificationLevel.nothing,
    });
  });

  test('an unknown level drops the entry like other malformed entries', () {
    final store = ChannelMuteStore.fromJson({
      'version': 1,
      'channels': {
        'a': {'muted': false, 'updatedAt': 1, 'level': 'loud'},
      },
    });
    expect(store.channels, isEmpty);
  });

  test('channels with a NIP-24 bot member default to mentions', () {
    final bot = 'b' * 64;
    final human = 'c' * 64;
    NostrEvent event(
      int kind,
      String pubkey,
      List<List<String>> tags, [
      String content = '',
    ]) => NostrEvent(
      id: '$kind$pubkey',
      pubkey: pubkey,
      createdAt: 1,
      kind: kind,
      tags: tags,
      content: content,
      sig: '',
    );
    final keys = notificationAgentKeys(
      [
        event(39002, 'r' * 64, [
          ['d', 'agents'],
          ['p', bot],
        ]),
        event(39002, 'r' * 64, [
          ['d', 'people'],
          ['p', human],
        ]),
      ],
      [
        event(0, bot, [], jsonEncode({'bot': true})),
        event(0, human, [], jsonEncode({'name': 'ann'})),
      ],
    );
    expect(keys.botPubkeys, {bot});
    expect(keys.agentChannelIds, {'agents'});
    Channel channel(String id, String type) => Channel(
      id: id,
      name: id,
      channelType: type,
      visibility: 'private',
      description: '',
      createdBy: 'x',
      createdAt: DateTime(2026),
      memberCount: 2,
    );
    expect(
      defaultChannelNotificationLevel(channel('agents', 'stream'), keys),
      ChannelNotificationLevel.mentions,
    );
    expect(
      defaultChannelNotificationLevel(channel('people', 'stream'), keys),
      ChannelNotificationLevel.all,
    );
    expect(
      defaultChannelNotificationLevel(channel('agents', 'dm'), keys),
      ChannelNotificationLevel.all,
    );
  });
}
