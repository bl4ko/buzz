import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/relay/relay.dart';
import '../channels/channel.dart';
import '../channels/channel_management_provider.dart';
import '../channels/channels_provider.dart';
import 'dm_resurface.dart';
import 'feed_item.dart';
import 'inbox_item.dart';
import 'activity_projection.dart';
import '../channels/channel_mutes/channel_mutes_provider.dart';
import '../channels/thread_follows/thread_follows_provider.dart';

typedef DmResurfaceAction = Future<String> Function(List<String> pubkeys);

final dmResurfaceActionProvider = Provider<DmResurfaceAction>(
  (ref) => (pubkeys) async {
    final channel = await ref
        .read(channelActionsProvider)
        .openDm(pubkeys: pubkeys);
    return channel.id;
  },
);

class ActivityNotifier extends AsyncNotifier<HomeFeedResponse> {
  static const _addressedKinds = [
    1,
    7,
    9,
    40002,
    43001,
    43002,
    43003,
    43004,
    43005,
    43006,
    45001,
    45003,
    46010,
    46011,
    46012,
  ];

  void Function()? _unsubscribeAddressed;
  final List<void Function()> _unsubscribeDms = [];
  final List<void Function()> _unsubscribeChannels = [];
  final List<void Function()> _unsubscribeHiddenDms = [];
  Timer? _liveRefreshTimer;
  Future<void>? _refreshInFlight;
  int? _refreshGeneration;
  bool _refreshQueued = false;
  int _subscriptionGeneration = 0;
  // Per-hidden-channel resurface coalescing. Presence of a key means an attempt
  // is in flight; the entry records the owning subscription generation and
  // whether a follower event arrived while it was running, so a failed reopen
  // re-runs instead of dropping the follower. The entry is generation-owned so
  // a follower on a rebuilt subscription starts its own attempt instead of
  // coalescing into a suspended old-generation attempt that will never resume.
  final Map<String, _PendingResurface> _pendingDmResurfaceRetry = {};
  String? _dmResurfaceScope;

  @override
  Future<HomeFeedResponse> build() async {
    ref.watch(relayConfigProvider);
    final sessionState = ref.watch(relaySessionProvider);
    ref.watch(channelsProvider.select(_channelKey));
    ref.watch(channelMutesProvider.select((state) => state.store));
    ref.watch(threadFollowsProvider);

    final generation = ++_subscriptionGeneration;
    final subscriptionSince = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 5;
    final currentPubkey = ref.read(myPubkeyProvider)?.toLowerCase();
    final currentScope =
        '${ref.read(relayConfigProvider).baseUrl}\u0000$currentPubkey';
    if (_dmResurfaceScope != currentScope) {
      _dmResurfaceScope = currentScope;
      _pendingDmResurfaceRetry.clear();
    }
    _clearLiveSubscriptions();
    ref.onDispose(() {
      _subscriptionGeneration += 1;
      _clearLiveSubscriptions();
    });

    final response = await _fetch();
    if (sessionState.status == SessionStatus.connected &&
        generation == _subscriptionGeneration) {
      unawaited(_subscribeLive(generation, since: subscriptionSince));
    }
    return response;
  }

  Future<void> _subscribeLive(int generation, {required int since}) async {
    final myPk = ref.read(myPubkeyProvider);
    if (myPk == null || generation != _subscriptionGeneration) return;

    final session = ref.read(relaySessionProvider.notifier);
    try {
      final unsubscribeAddressed = await session.subscribe(
        NostrFilter(
          kinds: _addressedKinds,
          tags: {
            '#p': [myPk],
          },
          since: since,
          limit: 100,
        ),
        (event) => _handleAddressedLiveEvent(event, generation),
      );
      if (generation != _subscriptionGeneration) {
        unsubscribeAddressed();
        return;
      }
      _unsubscribeAddressed = unsubscribeAddressed;

      final channels =
          ref.read(channelsProvider).asData?.value ?? const <Channel>[];
      final dmChannelIds = [
        for (final channel in channels)
          if (channel.isDm && channel.isMember) channel.id,
      ];
      // The relay rejects a REQ whose explicit `#h` values exceed
      // [kMaxExplicitChannelValues]. A single over-cap visible-DM REQ would be
      // rejected and, hitting the outer catch, abort the whole live setup —
      // including the hidden batches below — so more than that many visible DMs
      // used to silently disable resurfacing. Batch it under the same cap so no
      // single REQ can be rejected for size and a per-batch rejection stays
      // isolated to that batch.
      final visibleUnsubscribers = await _subscribeChannelBatches(
        session,
        generation,
        channelIds: dmChannelIds,
        kinds: const [9],
        since: since,
        onEvent: (_) => _scheduleLiveRefresh(generation),
      );
      if (visibleUnsubscribers == null) return;
      _unsubscribeDms.addAll(visibleUnsubscribers);
      final channelUnsubscribers = await _subscribeChannelBatches(
        session,
        generation,
        channelIds: [
          for (final channel in channels)
            if (channel.isMember && !channel.isArchived) channel.id,
        ],
        kinds: const [
          ...EventKind.channelMessageEventKinds,
          EventKind.reaction,
          EventKind.deletion,
          EventKind.nip29DeleteEvent,
          EventKind.streamMessageEdit,
        ],
        since: since,
        onEvent: (_) => _scheduleLiveRefresh(generation),
      );
      if (channelUnsubscribers == null) return;
      _unsubscribeChannels.addAll(channelUnsubscribers);

      // Resurface trigger: hidden DMs are dropped from the visible-DM sub above,
      // so subscribe to them separately. Channel messages carry a channel_id and
      // the relay only fans channel-scoped events to channel-scoped subs, so an
      // `#h` filter (never `#p`, which the relay treats as global) is required.
      // Hiding never drops membership, so `#h` authorization holds. The hidden
      // set is batched under the same cap and owned by this generation, so an
      // over-limit hidden set no longer silently disables resurfacing.
      final hiddenDmIds = ref
          .read(channelsProvider.notifier)
          .hiddenDmIds
          .toList();
      final hiddenUnsubscribers = await _subscribeChannelBatches(
        session,
        generation,
        channelIds: hiddenDmIds,
        kinds: EventKind.channelMessageEventKinds,
        since: since,
        onEvent: (event) => _handleHiddenDmLiveEvent(event, generation),
      );
      if (hiddenUnsubscribers == null) return;
      _unsubscribeHiddenDms.addAll(hiddenUnsubscribers);
    } catch (error) {
      if (generation == _subscriptionGeneration) {
        debugPrint('[ActivityNotifier] live subscription failed: $error');
      }
    }
  }

  /// Subscribes to a channel-scoped live feed split into batches that never
  /// exceed [kMaxExplicitChannelValues] explicit `#h` values, since the relay
  /// rejects a REQ that does. Each batch is its own subscription owned by
  /// [generation]. The generation is checked before every `subscribe` and
  /// immediately after each await, so teardown mid-setup disposes everything
  /// this call already opened and stops issuing REQs. A single batch's
  /// rejection is isolated so later batches still register.
  ///
  /// Returns the accumulated unsubscribers for the caller to retain, or `null`
  /// if a newer generation superseded this call — in which case it has already
  /// torn down everything it opened and the caller must return without
  /// publishing into a field the successor already cleared.
  Future<List<void Function()>?> _subscribeChannelBatches(
    RelaySessionNotifier session,
    int generation, {
    required List<String> channelIds,
    required List<int> kinds,
    required int since,
    required void Function(NostrEvent) onEvent,
  }) async {
    final unsubscribers = <void Function()>[];
    for (
      var start = 0;
      start < channelIds.length;
      start += kMaxExplicitChannelValues
    ) {
      // Never open a batch REQ for a superseded generation: check before each
      // subscribe so teardown mid-setup stops issuing new REQs, and tear down
      // everything this call already opened.
      if (generation != _subscriptionGeneration) {
        for (final unsubscribe in unsubscribers) {
          unsubscribe();
        }
        return null;
      }
      final end = start + kMaxExplicitChannelValues < channelIds.length
          ? start + kMaxExplicitChannelValues
          : channelIds.length;
      final batch = channelIds.sublist(start, end);
      try {
        final unsubscribe = await session.subscribe(
          NostrFilter(
            kinds: kinds,
            tags: {'#h': batch},
            since: since,
            limit: 100,
          ),
          onEvent,
        );
        // A newer generation may have superseded us while this batch's REQ was
        // in flight. Dispose the just-resolved subscription plus every batch
        // this call already opened, and stop without initiating another REQ.
        if (generation != _subscriptionGeneration) {
          unsubscribe();
          for (final accumulated in unsubscribers) {
            accumulated();
          }
          return null;
        }
        unsubscribers.add(unsubscribe);
      } catch (error) {
        // Superseded while this batch's REQ was rejected: tear down what we
        // opened and stop rather than initiating another REQ.
        if (generation != _subscriptionGeneration) {
          for (final accumulated in unsubscribers) {
            accumulated();
          }
          return null;
        }
        // One batch's REQ was rejected; keep subscribing the rest so a
        // partially-rejected set still covers every other batch.
        debugPrint(
          '[ActivityNotifier] channel batch subscription failed: $error',
        );
      }
    }
    // A newer generation may have superseded us after the final batch settled;
    // tear down every batch this call opened so none leak past the generation
    // that owns them.
    if (generation != _subscriptionGeneration) {
      for (final unsubscribe in unsubscribers) {
        unsubscribe();
      }
      return null;
    }
    return unsubscribers;
  }

  void _handleAddressedLiveEvent(NostrEvent event, int generation) {
    _scheduleLiveRefresh(generation);
  }

  void _handleHiddenDmLiveEvent(NostrEvent event, int generation) {
    if (generation != _subscriptionGeneration) return;
    final myPk = ref.read(myPubkeyProvider);
    if (myPk == null || !isIncomingChannelMessageFromOther(event, myPk)) return;
    _scheduleLiveRefresh(generation);
    if (!ref.read(channelsProvider.notifier).hasLoaded) {
      unawaited(
        _resurfaceAfterChannelDiscovery(event, myPk, _dmResurfaceScope),
      );
      return;
    }
    unawaited(_resurfaceHiddenDm(event, myPk, generation));
  }

  Future<void> _resurfaceAfterChannelDiscovery(
    NostrEvent event,
    String myPk,
    String? expectedScope,
  ) async {
    try {
      await ref.read(channelsProvider.future);
    } catch (error) {
      if (expectedScope == _dmResurfaceScope) {
        debugPrint(
          '[ActivityNotifier] channel discovery failed before DM resurface: $error',
        );
      }
      return;
    }
    if (expectedScope != _dmResurfaceScope) return;
    await _resurfaceHiddenDm(event, myPk, _subscriptionGeneration);
  }

  Future<void> _resurfaceHiddenDm(
    NostrEvent event,
    String myPk,
    int generation,
  ) async {
    final channelId = event.channelId;
    if (channelId == null || generation != _subscriptionGeneration) return;
    final channelsNotifier = ref.read(channelsProvider.notifier);
    if (!channelsNotifier.hasLoaded ||
        !channelsNotifier.hiddenDmIds.contains(channelId)) {
      return;
    }
    // Coalesce per channel within a generation: a concurrent follower for the
    // same DM marks the in-flight attempt for retry rather than being dropped,
    // so a failed reopen re-runs instead of leaving the row hidden. A follower
    // whose attempt was started by a superseded generation does not coalesce —
    // that attempt can never resume, so this generation starts a fresh one.
    final existing = _pendingDmResurfaceRetry[channelId];
    if (existing != null && existing.generation == generation) {
      existing.retry = true;
      return;
    }
    final pending = _PendingResurface(generation);
    _pendingDmResurfaceRetry[channelId] = pending;

    try {
      do {
        pending.retry = false;
        try {
          final members = await ref.read(
            channelMembersProvider(channelId).future,
          );
          if (generation != _subscriptionGeneration) return;
          final peers = dmPeerPubkeysFromMembers(
            members.map((member) => member.pubkey),
            myPk,
          );
          if (peers.isEmpty) return;
          final openedChannelId = await ref.read(dmResurfaceActionProvider)(
            peers.toList(),
          );
          if (generation != _subscriptionGeneration) return;
          if (openedChannelId != channelId) {
            throw StateError('Relay reopened a different DM conversation.');
          }
          return;
        } catch (error) {
          if (generation == _subscriptionGeneration) {
            debugPrint(
              '[ActivityNotifier] failed to resurface hidden DM $channelId: $error',
            );
          }
        }
      } while (pending.retry && generation == _subscriptionGeneration);
    } finally {
      // Only clear the entry if it is still the one this attempt installed; a
      // newer generation may have replaced it, and stomping that entry would
      // let its follower be dropped.
      if (identical(_pendingDmResurfaceRetry[channelId], pending)) {
        _pendingDmResurfaceRetry.remove(channelId);
      }
    }
  }

  void _scheduleLiveRefresh(int generation) {
    if (generation != _subscriptionGeneration) return;
    _liveRefreshTimer?.cancel();
    _liveRefreshTimer = Timer(
      const Duration(milliseconds: 50),
      () => unawaited(_queueRefresh(generation)),
    );
  }

  Future<void> _queueRefresh(int generation) {
    if (generation != _subscriptionGeneration) return Future.value();
    _refreshQueued = true;
    final inFlight = _refreshInFlight;
    if (_refreshGeneration == generation && inFlight != null) {
      return inFlight;
    }

    _refreshGeneration = generation;
    final future = _drainRefreshQueue(generation);
    _refreshInFlight = future;
    return future;
  }

  Future<void> _drainRefreshQueue(int generation) async {
    try {
      do {
        _refreshQueued = false;
        try {
          final next = await _fetch();
          if (generation != _subscriptionGeneration) return;
          state = AsyncData(next);
        } catch (error) {
          if (generation != _subscriptionGeneration) return;
          debugPrint(
            '[ActivityNotifier] inbox refresh failed; retaining feed: $error',
          );
        }
      } while (_refreshQueued && generation == _subscriptionGeneration);
    } finally {
      if (_refreshGeneration == generation) {
        _refreshInFlight = null;
        _refreshGeneration = null;
        _refreshQueued = false;
      }
    }
  }

  void _clearLiveSubscriptions() {
    _liveRefreshTimer?.cancel();
    _liveRefreshTimer = null;
    _refreshInFlight = null;
    _refreshGeneration = null;
    _refreshQueued = false;
    _unsubscribeAddressed?.call();
    _unsubscribeAddressed = null;
    for (final unsubscribe in _unsubscribeDms) {
      unsubscribe();
    }
    _unsubscribeDms.clear();
    for (final unsubscribe in _unsubscribeChannels) {
      unsubscribe();
    }
    _unsubscribeChannels.clear();
    for (final unsubscribe in _unsubscribeHiddenDms) {
      unsubscribe();
    }
    _unsubscribeHiddenDms.clear();
  }

  /// Stable identity for the joined DM channel set: null while channels are
  /// loading, otherwise the sorted member-DM ids. Keeps unrelated channel
  /// updates from refetching the feed.
  static String? _channelKey(AsyncValue<List<Channel>> channels) {
    final value = channels.asData?.value;
    if (value == null) return null;
    final ids = [
      for (final channel in value)
        if (channel.isMember && !channel.isArchived) channel.id,
    ]..sort();
    return ids.join(',');
  }

  Future<HomeFeedResponse> _fetch() async {
    final myPk = ref.read(myPubkeyProvider);
    if (myPk == null) {
      return HomeFeedResponse(
        mentions: const [],
        needsAction: const [],
        activity: const [],
        agentActivity: const [],
      );
    }

    final session = ref.read(relaySessionProvider.notifier);

    final channelIds = [
      for (final channel
          in ref.read(channelsProvider).asData?.value ?? const <Channel>[])
        if (channel.isMember && !channel.isArchived) channel.id,
    ];
    final interestedRootIds = {
      ...ref.read(channelsProvider.notifier).threadInterestRootIds,
      ...ref.read(threadFollowsProvider).followedRootIds,
    };
    final filters = <NostrFilter>[
      NostrFilter(
        kinds: const [9, 40002, 1, 7, 45001, 45003],
        tags: {
          '#p': [myPk],
        },
        limit: 100,
      ),
      NostrFilter(
        kinds: const [46010, 46011, 46012],
        tags: {
          '#p': [myPk],
        },
        limit: 20,
      ),
      NostrFilter(
        kinds: const [43001, 43002, 43003, 43004, 43005, 43006],
        tags: {
          '#p': [myPk],
        },
        limit: 20,
      ),
      for (
        var start = 0;
        start < channelIds.length;
        start += kMaxExplicitChannelValues
      )
        NostrFilter(
          kinds: const [
            ...EventKind.channelMessageEventKinds,
            EventKind.reaction,
            EventKind.deletion,
            EventKind.nip29DeleteEvent,
            EventKind.streamMessageEdit,
          ],
          tags: {
            '#h': channelIds
                .skip(start)
                .take(kMaxExplicitChannelValues)
                .toList(),
          },
          limit: 100,
        ),
      if (channelIds.isNotEmpty)
        NostrFilter(
          kinds: EventKind.channelMessageEventKinds,
          authors: [myPk],
          limit: 100,
        ),
    ];
    final events = [...await _queryWithWebSocketFallback(session, filters)];
    final fetchedIds = {for (final event in events) event.id};
    final missingTargets = {
      for (final event in events)
        if (event.kind == EventKind.reaction)
          for (final tag
              in event.tags
                  .where((tag) => tag.length > 1 && tag[0] == 'e')
                  .toList()
                  .reversed
                  .take(1))
            if (!fetchedIds.contains(tag[1])) tag[1],
    }.take(100).toList();
    if (missingTargets.isNotEmpty) {
      events.addAll(
        await _queryWithWebSocketFallback(session, [
          NostrFilter(
            kinds: EventKind.channelMessageEventKinds,
            ids: missingTargets,
            limit: missingTargets.length,
          ),
        ]),
      );
    }
    final rootIds = {
      ...interestedRootIds,
      for (final event in events)
        if (event.pubkey.toLowerCase() == myPk.toLowerCase() &&
            EventKind.channelMessageEventKinds.contains(event.kind))
          event.threadReference.rootId ?? event.id,
    }.toList();
    if (rootIds.isNotEmpty) {
      events.addAll(
        await _queryWithWebSocketFallback(session, [
          for (
            var start = 0;
            start < rootIds.length;
            start += kMaxExplicitChannelValues
          )
            NostrFilter(
              kinds: EventKind.channelMessageEventKinds,
              tags: {
                '#e': rootIds
                    .skip(start)
                    .take(kMaxExplicitChannelValues)
                    .toList(),
              },
              limit: 100,
            ),
        ]),
      );
    }
    return buildActivityFeed(
      events,
      myPubkey: myPk,
      channelIds: channelIds.toSet(),
      interestedRootIds: interestedRootIds,
      mutedChannelIds: {
        for (final entry
            in ref.read(channelMutesProvider).store.channels.entries)
          if (entry.value.muted) entry.key,
      },
    );
  }

  Future<List<NostrEvent>> _queryWithWebSocketFallback(
    RelaySessionNotifier session,
    List<NostrFilter> filters,
  ) async {
    try {
      return await session.queryRelay(filters);
    } catch (error) {
      debugPrint(
        '[ActivityNotifier] batched history query failed; '
        'using bounded websocket fallback: $error',
      );
    }

    const fallbackConcurrency = 4;
    final events = <NostrEvent>[];
    for (var start = 0; start < filters.length; start += fallbackConcurrency) {
      final end = start + fallbackConcurrency < filters.length
          ? start + fallbackConcurrency
          : filters.length;
      final results = await Future.wait(
        filters
            .sublist(start, end)
            .map((filter) => session.fetchHistory(filter)),
      );
      for (final result in results) {
        events.addAll(result);
      }
    }
    return events;
  }

  Future<void> refresh() async {
    await _queueRefresh(_subscriptionGeneration);
  }
}

/// A generation-owned, in-flight hidden-DM resurface attempt. `generation` ties
/// the entry to the subscription that started it so a follower on a rebuilt
/// subscription never coalesces into a suspended attempt that will never
/// resume; `retry` records that a follower arrived mid-attempt.
class _PendingResurface {
  _PendingResurface(this.generation);

  final int generation;
  bool retry = false;
}

final activityProvider =
    AsyncNotifierProvider<ActivityNotifier, HomeFeedResponse>(
      ActivityNotifier.new,
    );

/// Conversation-grouped inbox rows derived from the raw feed. DM messages
/// group by DM channel so one conversation renders as one row.
final inboxItemsProvider = Provider<List<InboxItem>>((ref) {
  final feed = ref.watch(activityProvider).value;
  if (feed == null) return const [];
  final dmChannelIds = {
    for (final channel
        in ref.watch(channelsProvider).asData?.value ?? const <Channel>[])
      if (channel.isDm) channel.id,
  };
  return buildInboxItems(feed.all, isDmChannel: dmChannelIds.contains);
});
