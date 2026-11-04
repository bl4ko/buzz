part of '../channel_detail_page.dart';

extension _UnreadBoundary on _MessageList {
  void _useUnreadBoundary({
    required ValueNotifier<String?> oldestUnreadMessageId,
    required ValueNotifier<bool> unreadBoundaryLoadFailed,
    required ObjectRef<int> unreadBoundaryFetchCount,
    required ObjectRef<bool> boundaryFetchInFlight,
    required ValueNotifier<int> unreadBoundaryReachedOldestCount,
    required bool hasUnreadDeepLink,
    required ValueNotifier<bool> hasUserScrolled,
    required ValueNotifier<bool> isUnreadNavigationDismissed,
    required ValueNotifier<bool> followsLatest,
    required ValueNotifier<bool> isAtLatest,
    required ValueNotifier<String?> unreadAnchorId,
  }) {
    useEffect(
      () {
        if (!hasInitialUnread ||
            oldestUnreadMessageId.value != null ||
            unreadBoundaryLoadFailed.value ||
            entries.isEmpty) {
          return null;
        }

        bool isLoadedTarget(String id) =>
            entries.any((entry) => entry.message.id == id) &&
            !notifier.isDetachedDeepLinkEvent(id);
        final hasLoadedOrdinaryTarget =
            initialOldestOrdinaryUnreadMessageId != null &&
            isLoadedTarget(initialOldestOrdinaryUnreadMessageId!);
        final hasLoadedForcedTarget = initialForcedUnreadMessageIds.any(
          isLoadedTarget,
        );
        final hasKnownTarget =
            initialOldestOrdinaryUnreadMessageId != null ||
            initialForcedUnreadMessageIds.isNotEmpty;
        final hasLoadedFetchTarget =
            initialOldestOrdinaryUnreadMessageId != null
            ? hasLoadedOrdinaryTarget
            : hasLoadedForcedTarget;
        final isTargetMissing =
            hasKnownTarget && !hasLoadedFetchTarget && !notifier.reachedOldest;
        if (isTargetMissing && (hasUnreadDeepLink || notifier.isSyncing)) {
          return null;
        }
        final canFetchTarget =
            isTargetMissing && unreadBoundaryFetchCount.value < 4;
        if (canFetchTarget) {
          unreadBoundaryFetchCount.value += 1;
          var cancelled = false;
          boundaryFetchInFlight.value = true;
          unawaited(
            Future<void>(() async {
              final loaded = await notifier.fetchOlder().whenComplete(
                () => boundaryFetchInFlight.value = false,
              );
              if (cancelled || loaded) return;
              if (notifier.reachedOldest) {
                unreadBoundaryReachedOldestCount.value += 1;
              } else {
                unreadBoundaryLoadFailed.value = true;
              }
            }),
          );
          return () => cancelled = true;
        }

        if (isTargetMissing) {
          unreadBoundaryLoadFailed.value = true;
        }

        final ordinaryUnread = entries
            .where(
              (entry) =>
                  initialOrdinaryUnreadMessageIds.contains(entry.message.id),
            )
            .map((entry) => entry.message)
            .firstOrNull;
        final forcedUnread = entries
            .where(
              (entry) =>
                  initialForcedUnreadMessageIds.contains(entry.message.id),
            )
            .map((entry) => entry.message)
            .firstOrNull;
        final candidates = [ordinaryUnread, forcedUnread].nonNulls.toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        final targetId = candidates.firstOrNull?.id;
        oldestUnreadMessageId.value = targetId;
        if (targetId != null &&
            initialChannelWasRead &&
            !hasUnreadDeepLink &&
            !hasUserScrolled.value &&
            !notifier.isDetachedDeepLinkEvent(targetId)) {
          isUnreadNavigationDismissed.value = true;
          followsLatest.value = false;
          isAtLatest.value = false;
          unreadAnchorId.value = targetId;
        }
        return null;
      },
      [
        hasInitialUnread,
        hasUnreadDeepLink,
        initialOrdinaryUnreadMessageIds,
        initialOldestOrdinaryUnreadMessageId,
        initialForcedUnreadMessageIds,
        entries.length,
        allMessages.length, // A page of hidden notices adds no entry.
        notifier.reachedOldest,
        notifier.isSyncing,
        unreadBoundaryLoadFailed.value,
      ],
    );
  }
}

// Newer rows shift reversed indexes; hold the target until the user scrolls.
void _useUnreadAnchorJump(
  BuildContext context,
  ItemScrollController itemScrollController,
  int? targetIndex, {
  required ValueNotifier<bool> followsLatest,
  required ValueNotifier<bool> hasUserScrolled,
}) {
  useEffect(() {
    if (targetIndex == null) return null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted ||
          !itemScrollController.isAttached ||
          followsLatest.value ||
          hasUserScrolled.value) {
        return;
      }
      itemScrollController.jumpTo(index: targetIndex, alignment: 0.35);
    });
    return null;
  }, [targetIndex]);
}

class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider();

  @override
  Widget build(BuildContext context) {
    final lineColor = context.colors.primary.withValues(alpha: 0.4);
    return Padding(
      key: const ValueKey('channel-unread-divider'),
      padding: const EdgeInsets.symmetric(vertical: Grid.xxs + Grid.quarter),
      child: Row(
        children: [
          Expanded(child: Divider(height: 1, thickness: 1, color: lineColor)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Grid.xxs),
            child: Text(
              'NEW',
              semanticsLabel: 'New messages',
              style: context.textTheme.labelSmall?.copyWith(
                color: context.colors.primary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Expanded(child: Divider(height: 1, thickness: 1, color: lineColor)),
        ],
      ),
    );
  }
}
