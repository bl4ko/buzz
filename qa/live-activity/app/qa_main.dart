import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'main.dart' show runBuzzApp;
import 'shared/community/community.dart';
import 'shared/community/community_storage.dart';

const _relay = String.fromEnvironment('QA_RELAY');
const _pub = String.fromEnvironment('QA_PUB');
const _nsec = String.fromEnvironment('QA_NSEC');
const _seededKey = 'qa.live_activity.seeded';

class _LockedKeychain extends MethodChannelFlutterSecureStorage {
  _LockedKeychain(this._flag);

  final File _flag;

  bool get _locked => _flag.existsSync();

  Future<T> _guard<T>(Future<T> Function() body) async {
    if (!_locked) return body();
    throw PlatformException(
      code: 'Unexpected security result code',
      message: 'Code: -25308, Message: User interaction is not allowed.',
      details: -25308,
    );
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) => _guard(() => super.read(key: key, options: options));

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) => _guard(() => super.write(key: key, value: value, options: options));

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) => _guard(() => super.delete(key: key, options: options));

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) => _guard(() => super.containsKey(key: key, options: options));

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) =>
      _guard(() => super.readAll(options: options));

  @override
  Future<void> deleteAll({required Map<String, String> options}) =>
      _guard(() => super.deleteAll(options: options));

  @override
  Future<bool?> isCupertinoProtectedDataAvailable() async => !_locked;

  @override
  Stream<bool> get onCupertinoProtectedDataAvailabilityChanged =>
      Stream.periodic(
        const Duration(milliseconds: 250),
        (_) => !_locked,
      ).distinct();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final library = await getLibraryDirectory();
  FlutterSecureStoragePlatform.instance = _LockedKeychain(
    File('${library.path}/qa-protected-data-unavailable'),
  );
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString(_seededKey) != _pub) {
    final community = Community.create(
      name: 'QA',
      relayUrl: _relay,
      pubkey: _pub,
      nsec: _nsec,
    ).copyWith(pushNotificationsEnabled: true);
    final storage = CommunityStorage();
    await storage.saveAll([community]);
    await storage.saveActiveId(community.id);
    await prefs.setString(_seededKey, _pub);
  }
  await runBuzzApp(const App());
}
