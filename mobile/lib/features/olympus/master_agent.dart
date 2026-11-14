import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/deeplink/deep_link.dart';
import '../../shared/deeplink/pending_deep_link_provider.dart';
import '../../shared/relay/relay.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/feedback_snackbar.dart';
import '../activity/compose_drafts_provider.dart';
import '../channels/channel.dart';
import '../channels/channel_detail_page.dart';
import '../channels/channel_management_provider.dart';
import '../channels/channel_unread.dart';
import '../channels/channels_provider.dart';
import '../../shared/read_state/read_state_provider.dart';
import 'olympus_provider.dart';
import 'olympus_state.dart';
import 'olympus_widgets.dart';

/// The 1:1 DM with [peer] from the loaded list, if there is one.
Channel? findAgentDm(WidgetRef ref, String peer) {
  final channels = ref.read(channelsProvider).asData?.value ?? const [];
  final notifier = ref.read(channelsProvider.notifier);
  final me = ref.read(myPubkeyProvider);
  return channels
      .where(
        (channel) => isActiveDirectConversation(
          channel,
          notifier.cachedMembersForChannel(channel.id),
          me,
          peer,
        ),
      )
      .firstOrNull;
}

/// The master DM id while it is listed, so the list can hide it.
final masterDmChannelIdProvider = Provider<String?>((ref) {
  final key = ref.watch(olympusMasterProvider.select((m) => m?.publicKey));
  final me = ref.watch(myPubkeyProvider);
  final channels = ref.watch(channelsProvider).asData?.value;
  if (key == null || me == null || channels == null) return null;
  return channels
      .where((channel) {
        final keys = channel.participantPubkeys
            .map((pubkey) => pubkey.toLowerCase())
            .toSet();
        return channel.isDm &&
            channel.isMember &&
            !channel.isArchived &&
            keys.length == 2 &&
            keys.contains(key) &&
            keys.contains(me.toLowerCase());
      })
      .firstOrNull
      ?.id;
});

/// Opens (or creates) the DM with [peer]; a [draft] joins the saved draft.
Future<void> openAgentDm(
  BuildContext context,
  WidgetRef ref,
  String peer, {
  String? draft,
}) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final channel =
        findAgentDm(ref, peer) ??
        await ref.read(channelActionsProvider).openDm(pubkeys: [peer]);
    if (draft != null && draft.isNotEmpty) {
      final drafts = ref.read(composeDraftsProvider.notifier);
      final key = composeDraftKey(channel.id);
      drafts.save(
        key: key,
        channelId: channel.id,
        text: mergeAskDraft(drafts.textFor(key), draft),
        mentionKeys: drafts.draftFor(key)?.mentionKeys ?? const {},
      );
    }
    if (!navigator.mounted) return;
    await navigator.push<void>(
      MaterialPageRoute(
        allowSnapshotting: false,
        builder: (_) => ChannelDetailPage(channel: channel),
      ),
    );
  } catch (error) {
    messenger?.showFeedbackSnackBar(
      SnackBar(content: Text('Could not open the conversation. $error')),
      kind: ToastKind.error,
    );
  }
}

/// Opens the master DM with the quoted message as a draft. Never sends.
Future<void> askMaster(
  BuildContext context,
  WidgetRef ref, {
  String? quote,
  String? link,
}) async {
  final key = ref.read(olympusMasterProvider)?.publicKey;
  if (key == null) return;
  unawaited(HapticFeedback.lightImpact());
  await openAgentDm(
    context,
    ref,
    key,
    draft: buildAskDraft(quote: quote, link: link),
  );
}

/// `Ask <master>` label, or null when there is no master agent.
String? askMasterLabel(WidgetRef ref) {
  final master = ref.watch(olympusMasterProvider);
  return master == null ? null : 'Ask ${olympusAgentLabel(ref, master)}';
}

const _quickActions = MethodChannel('buzz/quick_actions');

/// Keeps the home-screen quick action and `buzz://olympus/ask` working.
void useMasterAgentShortcut(BuildContext context, WidgetRef ref) {
  final label = askMasterLabel(ref);
  useEffect(() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;
    unawaited(
      _quickActions
          .invokeMethod<void>('setAskMaster', {'title': label})
          .catchError((Object error) {
            debugPrint('olympus: quick action failed: $error');
          }),
    );
    return null;
  }, [label]);

  final link = ref.watch(pendingDeepLinkProvider);
  final master = ref.watch(olympusMasterProvider);
  final loaded = ref.watch(olympusProvider.select((s) => s.loaded));
  final channelsReady = ref.watch(
    channelsProvider.select((state) => state.hasValue),
  );
  useEffect(() {
    if (link is! AskMasterDeepLink || !loaded || !channelsReady) return null;
    final key = master?.publicKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted || ref.read(pendingDeepLinkProvider) != link) {
        return;
      }
      ref.read(pendingDeepLinkProvider.notifier).consume();
      if (key == null) {
        ScaffoldMessenger.maybeOf(context)?.showFeedbackSnackBar(
          const SnackBar(content: Text('No master agent in this community.')),
          kind: ToastKind.error,
        );
        return;
      }
      unawaited(openAgentDm(context, ref, key));
    });
    return null;
  }, [link, loaded, channelsReady, master?.publicKey]);
}

/// The master agent, pinned above Inbox on Messages.
class MasterAgentRow extends ConsumerWidget {
  const MasterAgentRow({super.key});

  static const double _avatar = 24;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final master = ref.watch(olympusMasterProvider);
    final key = master?.publicKey;
    if (master == null || key == null) return const SizedBox.shrink();
    final working = ref.watch(
      olympusWorkingAgentsProvider.select((agents) => agents.contains(key)),
    );
    ref.watch(olympusPendingCountProvider);
    final pending = ref
        .watch(olympusProvider)
        .pendingCount(olympusNow(), requesterKey: key);
    final dmId = ref.watch(masterDmChannelIdProvider);
    final unread = dmId != null && _unread(ref, dmId);
    final label = olympusAgentLabel(ref, master);
    final state = olympusDisplayState(master, working);
    return Semantics(
      key: const ValueKey('olympus-master-row'),
      button: true,
      label:
          '$label, master agent'
          '${pending > 0 ? ', $pending proposals' : ''}'
          '${unread ? ', unread' : ''}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: () {
          unawaited(HapticFeedback.lightImpact());
          unawaited(openAgentDm(context, ref, key));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Grid.gutter,
            vertical: Grid.inventoryRowInset,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    OlympusAgentAvatar(agent: master, size: _avatar),
                    if (state != OlympusDisplayState.starting)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: switch (state) {
                              OlympusDisplayState.working =>
                                context.colors.primary,
                              OlympusDisplayState.online =>
                                context.appColors.success,
                              _ => context.colors.outline,
                            },
                            border: Border.all(
                              color: context.theme.scaffoldBackgroundColor,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Grid.inventoryLabelGap),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: navigationChatTitleTextStyle.copyWith(
                    color: channelNavigationForeground(context, unread: unread),
                    fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: Grid.xxs),
              Text(
                working ? 'Working…' : 'Master',
                style: context.textTheme.labelMedium?.copyWith(
                  color: working
                      ? context.colors.primary
                      : navigationMetadataForeground(context),
                ),
              ),
              const Spacer(),
              if (pending > 0)
                OlympusCountBadge(count: pending)
              else if (unread)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.colors.primary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool _unread(WidgetRef ref, String channelId) {
    final channel = (ref.watch(channelsProvider).asData?.value ?? const [])
        .where((candidate) => candidate.id == channelId)
        .firstOrNull;
    if (channel == null) return false;
    final readState = ref.watch(readStateProvider);
    if (readState.effectiveTimestamp(channelId) == null) return false;
    return computeChannelListHighlights(
      channels: [channel],
      readState: readState,
      channelsNotifier: ref.read(channelsProvider.notifier),
    ).unread.contains(channelId);
  }
}
