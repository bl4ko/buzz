import 'dart:convert';

import 'user_profile.dart';

Map<String, Map<String, String>> parseAgentMedia(String content) {
  Object? decoded;
  try {
    decoded = jsonDecode(content);
  } on FormatException {
    return const {};
  }
  final media = decoded is Map ? decoded['buzz_agent_media'] : null;
  if (media is! Map || media.length > 32) return const {};
  return {
    for (final entry in media.entries)
      if (entry.key is String && entry.value is Map)
        (entry.key as String).toLowerCase(): {
          for (final field in ['picture', 'banner', 'buzz_model'])
            if (entry.value[field] is String)
              field: entry.value[field] as String,
        },
  };
}

UserProfile applyAgentMedia(UserProfile profile, UserProfile? owner) {
  if (profile.ownerPubkey == null || profile.ownerPubkey != owner?.pubkey) {
    return profile;
  }
  final media = owner!.agentMedia[profile.pubkey];
  if (media == null) return profile;
  return UserProfile(
    pubkey: profile.pubkey,
    displayName: profile.displayName,
    avatarUrl: media['picture'] ?? profile.avatarUrl,
    bannerUrl: media['banner'] ?? profile.bannerUrl,
    modelUrl: media['buzz_model'] ?? profile.modelUrl,
    about: profile.about,
    nip05Handle: profile.nip05Handle,
    ownerPubkey: profile.ownerPubkey,
    agentMedia: profile.agentMedia,
  );
}
