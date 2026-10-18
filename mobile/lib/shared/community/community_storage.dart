import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../storage/secure_storage.dart';
import '../storage/serial_queue.dart';

import 'community.dart';

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

  CommunityStorage({FlutterSecureStorage? secure})
    : _secure = secure ?? communitySecureStorage;

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

  static final _pendingInvites = SerialQueue();
  static const _pendingInvitePrefix = 'buzz_pending_invite_v1_';

  static String _pendingInviteKey(String relayUrl, String code) {
    final uri = Uri.parse(relayUrl);
    final origin = uri
        .replace(
          scheme: ['https', 'wss'].contains(uri.scheme) ? 'https' : 'http',
        )
        .origin;
    return '$_pendingInvitePrefix${sha256.convert(utf8.encode(jsonEncode([origin, code])))}';
  }

  /// Retain the claim identity before sending a request with uncertain outcomes.
  /// A failed read/write must never generate a replacement for an unknown key.
  Future<String> pendingInviteIdentity(
    String relayUrl,
    String code,
    String Function() generate,
  ) => _pendingInvites.run(() async {
    final key = _pendingInviteKey(relayUrl, code);
    final saved = await _read(key);
    if (saved != null) return saved;
    final nsec = generate();
    await _write(key, nsec);
    if (await _read(key) != nsec) {
      throw StateError('Could not retain the pending invite identity');
    }
    return nsec;
  });

  /// Retire the journal only after the destination identity is durably saved.
  Future<void> completePendingInvite(
    String relayUrl,
    String code,
    Community community,
  ) => _pendingInvites.run(() async {
    final saved = await loadAll();
    if (!saved.any(
      (item) => item.id == community.id && item.nsec == community.nsec,
    )) {
      return;
    }
    final key = _pendingInviteKey(relayUrl, code);
    if (await _read(key) == community.nsec) {
      await _delete(key);
    }
  });

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

  Future<void> remove(String id) => _pendingInvites.run(() async {
    final all = await loadAll();
    final removedKeys = all
        .where((item) => item.id == id)
        .map((item) => item.nsec)
        .whereType<String>()
        .toSet();
    if (removedKeys.isNotEmpty) {
      // Retire every journal copy before removing the saved community. If a
      // deletion fails, keep that community so sign-out can safely retry.
      final records = await _unlocked(_secure.readAll);
      for (final entry in records.entries) {
        if (entry.key.startsWith(_pendingInvitePrefix) &&
            removedKeys.contains(entry.value)) {
          await _delete(entry.key);
          if (await _read(entry.key) != null) {
            throw StateError('Could not remove the pending invite identity');
          }
        }
      }
    }
    all.removeWhere((w) => w.id == id);
    await _saveList(all);
  });

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

  Future<void> _write(String key, String value) =>
      _unlocked(() => _secure.write(key: key, value: value));

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
