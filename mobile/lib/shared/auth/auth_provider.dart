import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nostr/nostr.dart' as nostr;

import '../community/community.dart';
import '../community/community_provider.dart';
import '../community/community_storage.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthState {
  final AuthStatus status;
  final Community? community;

  const AuthState({required this.status, this.community});
}

/// Restores the active community without making connectivity load-bearing.
/// The relay session owns connection recovery after startup.
class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    // Read from storage directly — NOT from community providers.
    // Watching community providers here would create a circular dependency
    // because authenticateWithCommunity() writes to those providers.
    final storage = ref.read(communityStorageProvider);
    final communities = await _withPushCopies(storage, await storage.loadAll());
    if (communities.isEmpty) {
      return const AuthState(status: AuthStatus.unauthenticated);
    }

    var activeId = await storage.loadActiveId();
    while (communities.isNotEmpty) {
      final active =
          activeId != null && communities.any((w) => w.id == activeId)
          ? communities.firstWhere((w) => w.id == activeId)
          : communities.first;
      await storage.saveActiveId(active.id);

      if (_hasValidNsec(active.nsec)) {
        await syncCommunitySnapshot(ref, communities);
        return AuthState(status: AuthStatus.authenticated, community: active);
      }

      await storage.remove(active.id);
      communities.removeWhere((community) => community.id == active.id);
      activeId = null;
      ref.invalidate(communityListProvider);
      ref.invalidate(activeCommunityProvider);
    }

    await storage.clearActiveId();
    return const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<List<Community>> _withPushCopies(
    CommunityStorage storage,
    List<Community> communities,
  ) async {
    if (communities.isNotEmpty &&
        communities.every((community) => _hasValidNsec(community.nsec))) {
      return communities;
    }
    final merged = [...communities];
    var changed = false;
    for (final copy in await storage.recoverFromPushCopies()) {
      final index = merged.indexWhere((community) => community.id == copy.id);
      if (index < 0 && communities.isEmpty) {
        merged.add(copy);
        changed = true;
      } else if (index >= 0 && !_hasValidNsec(merged[index].nsec)) {
        merged[index] = merged[index].copyWith(
          pubkey: copy.pubkey,
          nsec: copy.nsec,
        );
        changed = true;
      }
    }
    if (changed) await storage.saveAll(merged);
    return merged;
  }

  /// Authenticate with a community. Saves it and switches to it.
  /// Writes to storage directly to avoid circular dependency with community
  /// providers.
  Future<void> authenticateWithCommunity(Community community) {
    return ref.read(communityTransitionProvider).runExclusive(() async {
      await ref.read(communityTransitionProvider).run();
      final storage = ref.read(communityStorageProvider);
      await storage.save(community);
      await storage.saveActiveId(community.id);
      await syncStoredCommunitySnapshot(ref);

      // Invalidate community providers so other consumers pick up the new data.
      ref.invalidate(communityListProvider);
      ref.invalidate(activeCommunityProvider);

      state = AsyncData(
        AuthState(status: AuthStatus.authenticated, community: community),
      );
    });
  }

  Future<void> signOut() {
    return () async {
      final storage = ref.read(communityStorageProvider);
      await ref
          .read(communityListProvider.notifier)
          .removeActiveCommunityForSignOut();

      // Community removal already persisted the outbox, deleted credentials,
      // selected the next active community, and removed NSE state. Authentication
      // only needs to publish the truthful resulting account state.
      final remaining = await storage.loadAll();
      ref.invalidate(activeCommunityProvider);
      if (remaining.isEmpty) {
        state = const AsyncData(AuthState(status: AuthStatus.unauthenticated));
        return;
      }
      ref.invalidateSelf();
      await future;
    }();
  }
}

bool _hasValidNsec(String? nsec) {
  if (nsec == null || nsec.isEmpty) return false;
  try {
    final decoded = nostr.Nip19.decode(payload: nsec);
    return decoded.prefix == nostr.Nip19Prefix.nsec &&
        decoded.data.length == 64;
  } catch (_) {
    return false;
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
