import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/relay/relay.dart';
import '../channel.dart';
import '../channels_provider.dart';
import 'channel_mutes_storage.dart';

class NotificationAgentKeys {
  final Set<String> botPubkeys;
  final Set<String> agentChannelIds;

  const NotificationAgentKeys({
    this.botPubkeys = const {},
    this.agentChannelIds = const {},
  });
}

bool isBotProfileContent(String content) {
  try {
    final decoded = jsonDecode(content);
    return decoded is Map && decoded['bot'] == true;
  } catch (_) {
    return false;
  }
}

NotificationAgentKeys notificationAgentKeys(
  Iterable<NostrEvent> rosters,
  Iterable<NostrEvent> profiles,
) {
  final botPubkeys = {
    for (final profile in profiles)
      if (profile.kind == 0 && isBotProfileContent(profile.content))
        profile.pubkey.toLowerCase(),
  };
  final latest = <String, NostrEvent>{};
  for (final roster in rosters) {
    final channelId = roster.getTagValue('d');
    if (channelId == null) continue;
    final current = latest[channelId];
    if (current == null || roster.createdAt > current.createdAt) {
      latest[channelId] = roster;
    }
  }
  return NotificationAgentKeys(
    botPubkeys: botPubkeys,
    agentChannelIds: {
      for (final MapEntry(key: channelId, value: roster) in latest.entries)
        if (roster.tags.any(
          (tag) =>
              tag.length > 1 &&
              tag[0] == 'p' &&
              botPubkeys.contains(tag[1].toLowerCase()),
        ))
          channelId,
    },
  );
}

ChannelNotificationLevel defaultChannelNotificationLevel(
  Channel channel,
  NotificationAgentKeys keys,
) {
  if (channel.channelType == 'dm') return ChannelNotificationLevel.all;
  return keys.agentChannelIds.contains(channel.id)
      ? ChannelNotificationLevel.mentions
      : ChannelNotificationLevel.all;
}

const _rosterLimit = 1000;
const _profileBatch = 200;

/// Bot keys (NIP-24 `bot: true`) among the members of the user's channels,
/// and the channels that have such a member.
final notificationAgentKeysProvider =
    FutureProvider.autoDispose<NotificationAgentKeys>((ref) async {
      final pubkey = ref.watch(myPubkeyProvider);
      ref.watch(
        channelsProvider.select(
          (channels) => channels.value?.map((channel) => channel.id).join(','),
        ),
      );
      if (pubkey == null || pubkey.isEmpty) {
        return const NotificationAgentKeys();
      }
      final session = ref.read(relaySessionProvider.notifier);
      final rosters = await session.fetchHistory(
        NostrFilter(
          kinds: const [39002],
          tags: {
            '#p': [pubkey],
          },
          limit: _rosterLimit,
        ),
      );
      final members = {
        for (final roster in rosters)
          for (final tag in roster.tags)
            if (tag.length > 1 && tag[0] == 'p') tag[1].toLowerCase(),
      }.toList();
      final profiles = <NostrEvent>[];
      for (var offset = 0; offset < members.length; offset += _profileBatch) {
        final end = (offset + _profileBatch).clamp(0, members.length);
        profiles.addAll(
          await session.fetchHistory(
            NostrFilters.profilesBatch(members.sublist(offset, end)),
          ),
        );
      }
      return notificationAgentKeys(rosters, profiles);
    });
