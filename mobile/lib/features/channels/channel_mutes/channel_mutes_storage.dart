import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/theme/community_theme_preference.dart';

/// Channel ids belong to one community, so the cache is keyed by relay as
/// well as identity. One identity can be paired with several communities.
String channelMutesKey(String pubkey, String relayUrl) =>
    'buzz.channel-mutes.v1:$pubkey:${Uri.encodeComponent(normalizeCommunityRelayUrl(relayUrl))}';

/// The earlier key, shared by every community of the identity.
String legacyChannelMutesKey(String pubkey) => 'buzz.channel-mutes.v1:$pubkey';

enum ChannelNotificationLevel {
  all('All new messages'),
  mentions('Mentions and DMs'),
  nothing('Nothing');

  const ChannelNotificationLevel(this.label);

  final String label;

  static ChannelNotificationLevel? parse(Object? value) {
    for (final level in values) {
      if (level.name == value) return level;
    }
    return null;
  }
}

class ChannelMuteEntry {
  final bool muted;
  final int updatedAt;
  final ChannelNotificationLevel? level;

  const ChannelMuteEntry({
    required this.muted,
    required this.updatedAt,
    this.level,
  });

  factory ChannelMuteEntry.forLevel(
    ChannelNotificationLevel? level,
    int updatedAt,
  ) => ChannelMuteEntry(
    muted: level == ChannelNotificationLevel.nothing,
    updatedAt: updatedAt,
    level: level,
  );

  /// The level the user chose, or null for the channel default. A mute from
  /// an older client is [ChannelNotificationLevel.nothing].
  ChannelNotificationLevel? get explicitLevel {
    if (muted) return ChannelNotificationLevel.nothing;
    return level == ChannelNotificationLevel.nothing ? null : level;
  }

  Map<String, dynamic> toJson() => {
    'muted': muted,
    'updatedAt': updatedAt,
    if (level != null) 'level': level!.name,
  };

  factory ChannelMuteEntry.fromJson(Map<String, dynamic> json) =>
      ChannelMuteEntry(
        muted: json['muted'] as bool,
        updatedAt: json['updatedAt'] as int,
        level: ChannelNotificationLevel.parse(json['level']),
      );
}

class ChannelMuteStore {
  final int version;
  final Map<String, ChannelMuteEntry> channels;

  const ChannelMuteStore({this.version = 1, this.channels = const {}});

  Map<String, dynamic> toJson() => {
    'version': version,
    'channels': {for (final e in channels.entries) e.key: e.value.toJson()},
  };

  factory ChannelMuteStore.fromJson(Map<String, dynamic> json) {
    final rawChannels = json['channels'];
    final channels = <String, ChannelMuteEntry>{};
    if (rawChannels is Map) {
      for (final entry in rawChannels.entries) {
        if (entry.key is String && entry.value is Map<String, dynamic>) {
          final v = entry.value as Map<String, dynamic>;
          if (v['muted'] is bool &&
              v['updatedAt'] is int &&
              (v['level'] == null ||
                  ChannelNotificationLevel.parse(v['level']) != null)) {
            channels[entry.key as String] = ChannelMuteEntry.fromJson(v);
          }
        }
      }
    }
    return ChannelMuteStore(version: 1, channels: channels);
  }
}

ChannelMuteStore mergeStores(ChannelMuteStore local, ChannelMuteStore remote) {
  // Per-channel max-updatedAt merge:
  // For each channel ID in the union, keep the entry with the highest updatedAt.
  final merged = <String, ChannelMuteEntry>{...local.channels};
  for (final entry in remote.channels.entries) {
    final existing = merged[entry.key];
    if (existing == null || entry.value.updatedAt > existing.updatedAt) {
      merged[entry.key] = entry.value;
    }
  }
  return ChannelMuteStore(channels: merged);
}

Map<String, ChannelNotificationLevel> explicitChannelLevels(
  ChannelMuteStore store,
) => {
  for (final entry in store.channels.entries)
    if (entry.value.explicitLevel != null)
      entry.key: entry.value.explicitLevel!,
};

class ChannelMutesStorage {
  final SharedPreferences _prefs;

  ChannelMutesStorage(this._prefs);

  ChannelMuteStore read(String pubkey, String relayUrl) {
    // The shared entry may hold another community's channels, and the relay
    // copy is authoritative, so drop it rather than let one community claim it.
    _prefs.remove(legacyChannelMutesKey(pubkey));
    final raw = _prefs.getString(channelMutesKey(pubkey, relayUrl));
    if (raw == null || raw.isEmpty) {
      return const ChannelMuteStore();
    }

    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic>) {
        return const ChannelMuteStore();
      }
      if (parsed['version'] != 1) {
        return const ChannelMuteStore();
      }
      return ChannelMuteStore.fromJson(parsed);
    } catch (_) {
      return const ChannelMuteStore();
    }
  }

  Future<bool> write(String pubkey, String relayUrl, ChannelMuteStore store) =>
      _prefs.setString(
        channelMutesKey(pubkey, relayUrl),
        jsonEncode(store.toJson()),
      );
}
