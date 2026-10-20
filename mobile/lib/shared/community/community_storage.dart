import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nostr/nostr.dart' as nostr;

import 'community.dart';

typedef SecureStorageWrite = Future<void> Function(String key, String value);

typedef PushIdentityCopies = Future<List<Map<Object?, Object?>>> Function();

const _secureStorageChannel = MethodChannel('buzz/secure_storage');

Future<void> _keychainWrite(String key, String value) => _secureStorageChannel
    .invokeMethod<void>('write', {'key': key, 'value': value});

Future<List<Map<Object?, Object?>>> _pushIdentityCopies() async {
  try {
    return await _secureStorageChannel.invokeListMethod<Map<Object?, Object?>>(
          'recoverCommunities',
        ) ??
        const [];
  } on MissingPluginException {
    return const [];
  }
}

Community? _recoveredCommunity(Map<Object?, Object?> copy) {
  final [id, name, relayUrl, pubkey, privateKey] = [
    for (final field in ['id', 'name', 'relayUrl', 'pubkey', 'privateKey'])
      copy[field],
  ];
  if (id is! String ||
      name is! String ||
      relayUrl is! String ||
      pubkey is! String ||
      privateKey is! String) {
    return null;
  }
  try {
    final keys = nostr.Keys(privateKey);
    if (keys.public != pubkey.toLowerCase()) return null;
    return Community.recovered(
      id: id,
      name: name,
      relayUrl: relayUrl,
      pubkey: keys.public,
      nsec: keys.nsec,
    );
  } catch (_) {
    return null;
  }
}

class CommunityStorage {
  static const _keyCommunities = 'buzz_communities';
  static const _keyActiveId = 'buzz_active_community_id';

  // Legacy keys for migration.
  static const _legacyCommunities = 'buzz_workspaces';
  static const _legacyActiveId = 'buzz_active_workspace_id';
  static const _legacyRelayUrl = 'buzz_relay_url';
  static const _legacyToken = 'buzz_token';
  static const _legacyPubkey = 'buzz_pubkey';
  static const _legacyNsec = 'buzz_nsec';
  static const _interactionNotAllowed = -25308;

  final FlutterSecureStorage _secure;
  final SecureStorageWrite? _inPlaceWrite;
  final PushIdentityCopies? _pushCopies;

  CommunityStorage({
    FlutterSecureStorage? secure,
    SecureStorageWrite? write,
    PushIdentityCopies? pushCopies,
  }) : _secure = secure ?? const FlutterSecureStorage(),
       _inPlaceWrite =
           write ??
           (secure == null && defaultTargetPlatform == TargetPlatform.iOS
               ? _keychainWrite
               : null),
       _pushCopies =
           pushCopies ??
           (secure == null && defaultTargetPlatform == TargetPlatform.iOS
               ? _pushIdentityCopies
               : null);

  Future<List<Community>> recoverFromPushCopies() async {
    final copies = _pushCopies;
    if (copies == null) return const [];
    return [
      for (final copy in await _unlocked(copies)) ?_recoveredCommunity(copy),
    ];
  }

  /// Load all communities. On first call, migrates legacy single-community
  /// credentials if present.
  Future<List<Community>> loadAll() async {
    final raw = await _read(_keyCommunities);
    if (raw != null) return _decodeList(raw);

    final legacyCommunities = await _read(_legacyCommunities);
    if (legacyCommunities != null) {
      final communities = _decodeList(legacyCommunities);
      await _saveList(communities);
      final legacyActiveId = await _read(_legacyActiveId);
      if (legacyActiveId != null) await saveActiveId(legacyActiveId);
      await _delete(_legacyCommunities);
      await _delete(_legacyActiveId);
      return communities;
    }

    // Migration: check for legacy single-community keys.
    final legacyUrl = await _read(_legacyRelayUrl);
    final legacyToken = await _read(_legacyToken);
    if (legacyUrl != null && legacyToken != null) {
      final legacyPubkey = await _read(_legacyPubkey);
      final legacyNsec = await _read(_legacyNsec);

      final name = Community.nameFromUrl(legacyUrl);
      final community = Community.create(
        name: name,
        relayUrl: legacyUrl,
        pubkey: legacyPubkey,
        nsec: legacyNsec,
        sensitiveActionPolicy: SensitiveActionPolicy.disabledByUser,
      );

      await _saveList([community]);
      await saveActiveId(community.id);

      // Delete legacy keys.
      await _delete(_legacyRelayUrl);
      await _delete(_legacyToken);
      await _delete(_legacyPubkey);
      await _delete(_legacyNsec);

      return [community];
    }

    return [];
  }

  Future<void> save(Community community) async {
    final all = await loadAll();
    final index = all.indexWhere((w) => w.id == community.id);
    if (index >= 0) {
      all[index] = community;
    } else {
      all.add(community);
    }
    await _saveList(all);
  }

  /// Replaces the complete stored community list in one secure-storage write.
  Future<void> saveAll(List<Community> communities) => _saveList(communities);

  Future<void> remove(String id) async {
    final all = await loadAll();
    all.removeWhere((w) => w.id == id);
    await _saveList(all);
  }

  Future<String?> loadActiveId() async {
    return _read(_keyActiveId);
  }

  Future<void> saveActiveId(String id) async {
    await _write(_keyActiveId, id);
  }

  Future<void> clearActiveId() async {
    await _delete(_keyActiveId);
  }

  List<Community> _decodeList(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((entry) => Community.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveList(List<Community> communities) async {
    final json = jsonEncode(communities.map((item) => item.toJson()).toList());
    await _write(_keyCommunities, json);
  }

  Future<String?> _read(String key) => _unlocked(() => _secure.read(key: key));

  Future<void> _write(String key, String value) => _unlocked(() async {
    final write = _inPlaceWrite;
    if (write != null) {
      try {
        return await write(key, value);
      } on MissingPluginException {
        await _secure.write(key: key, value: value);
        return;
      }
    }
    await _secure.write(key: key, value: value);
  });

  Future<void> _delete(String key) => _unlocked(() => _secure.delete(key: key));

  Future<T> _unlocked<T>(Future<T> Function() operation) async {
    while (true) {
      if (await _secure.isCupertinoProtectedDataAvailable() != false) {
        try {
          return await operation();
        } on PlatformException catch (error) {
          if (error.details != _interactionNotAllowed) rethrow;
        }
      }
      await _protectedDataAvailable();
    }
  }

  Future<void> _protectedDataAvailable() async {
    final changes = _secure.onCupertinoProtectedDataAvailabilityChanged;
    if (changes == null) {
      await Future<void>.delayed(const Duration(seconds: 1));
      return;
    }
    final available = Completer<void>();
    final subscription = changes.listen((value) {
      if (value && !available.isCompleted) available.complete();
    });
    try {
      if (await _secure.isCupertinoProtectedDataAvailable() == false) {
        await available.future;
      }
    } finally {
      await subscription.cancel();
    }
  }
}
