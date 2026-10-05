import 'package:buzz/features/channels/channel_management_provider.dart';
import 'package:buzz/features/profile/profile_media.dart';
import 'package:buzz/features/profile/profile_provider.dart';
import 'package:buzz/features/profile/user_profile_sheet.dart';
import 'package:buzz/shared/profile/user_cache_provider.dart';
import 'package:buzz/shared/profile/user_profile.dart';
import 'package:buzz/shared/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Cache extends UserCacheNotifier {
  _Cache(this.profile);
  final UserProfile profile;

  @override
  Map<String, UserProfile> build() => {profile.pubkey: profile};

  @override
  UserProfile? get(String pubkey) => profile;

  @override
  Future<bool> preload(List<String> pubkeys) async => true;
}

class _SaveProfile extends ProfileNotifier {
  _SaveProfile(this.fail);
  final bool fail;
  final List<String?> icons = [];
  final patches = <(String, String?, String?)>[];

  @override
  Future<UserProfile?> build() async => const UserProfile(pubkey: 'owner');

  @override
  Future<void> updateAgentMedia({
    required String agentPubkey,
    String? bannerUrl,
    String? modelUrl,
    String? avatarUrl,
  }) async {
    patches.add((agentPubkey, bannerUrl, modelUrl));
    icons.add(avatarUrl);
    if (fail) throw StateError('Save failed');
  }
}

void main() {
  final owner = 'a' * 64;
  final agent = 'b' * 64;

  testWidgets('icon controls save only the changed agent icon', (tester) async {
    final notifier = _SaveProfile(false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileProvider.overrideWith(() => notifier)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ProfileMediaEditor(
              agentPubkey: agent,
              profile: UserProfile(
                pubkey: agent,
                avatarUrl: 'https://example.com/icon.png',
                bannerUrl: 'https://example.com/banner.png',
                modelUrl: 'https://example.com/model.glb',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Upload icon'), findsOneWidget);
    await tester.tap(find.text('Remove icon'));
    await tester.pump();
    await tester.tap(find.text('Save profile media'));
    await tester.pumpAndSettle();
    expect(notifier.icons, ['']);
    expect(notifier.patches, [(agent, null, null)]);
  });

  Future<void> mount(WidgetTester tester, String viewer) async {
    final profile = UserProfile(
      pubkey: agent,
      displayName: 'Hermes',
      ownerPubkey: owner,
      bannerUrl: 'https://example.com/banner.png',
      modelUrl: 'https://example.com/model.glb',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userCacheProvider.overrideWith(() => _Cache(profile)),
          currentPubkeyProvider.overrideWithValue(viewer),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: UserProfileSheet(pubkey: agent)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('saved banner overlaps avatar; editor opens only from settings', (
    tester,
  ) async {
    await mount(tester, owner);
    expect(find.byType(ProfileMediaEditor), findsNothing);
    expect(find.text('View 3D model'), findsOneWidget);
    final banner = tester.getRect(find.byType(ProfileBanner));
    final avatar = tester.getRect(
      find.byKey(const ValueKey('selected-profile-avatar')),
    );
    expect(avatar.top, greaterThan(banner.top));
    expect(avatar.top, lessThan(banner.bottom));
    expect(avatar.bottom, greaterThan(banner.bottom));
    await tester.tap(find.byTooltip('Profile settings'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileMediaEditor), findsOneWidget);
    expect(find.text('Save profile media'), findsOneWidget);
    expect(
      tester
          .widget<ProfileMediaEditor>(find.byType(ProfileMediaEditor))
          .profile
          ?.bannerUrl,
      'https://example.com/banner.png',
    );
  });

  testWidgets('another user sees banner without edit controls', (tester) async {
    await mount(tester, 'c' * 64);
    expect(find.byType(ProfileBanner), findsOneWidget);
    expect(find.byTooltip('Profile settings'), findsNothing);
    expect(find.byType(ProfileMediaEditor), findsNothing);
  });
  for (final fail in [false, true]) {
    testWidgets('save callback follows confirmed result (failure: $fail)', (
      tester,
    ) async {
      final notifier = _SaveProfile(fail);
      var saved = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [profileProvider.overrideWith(() => notifier)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: ProfileMediaEditor(
                profile: UserProfile(
                  pubkey: agent,
                  bannerUrl: 'https://example.com/banner.png',
                ),
                agentPubkey: agent,
                onSaved: () => saved++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove banner'));
      await tester.pump();
      await tester.tap(find.text('Save profile media'));
      await tester.pumpAndSettle();
      expect(notifier.patches, [(agent, '', null)]);
      expect(saved, fail ? 0 : 1);
      if (fail) expect(find.text('Bad state: Save failed'), findsOneWidget);
    });
  }
}
