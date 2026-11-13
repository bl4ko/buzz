import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../features/channels/channel.dart';
import '../../features/channels/channel_mutes/channel_mutes_provider.dart';
import '../../features/channels/channel_mutes/channel_mutes_storage.dart';
import '../../features/channels/channel_mutes/channel_notification_levels.dart';
import '../../features/channels/channels_provider.dart';
import '../auth/auth.dart';
import '../relay/relay_provider.dart';
import 'push_subscription.dart';
import 'push_relay_capability_provider.dart';
import 'push_setup_recovery.dart';

/// Keeps the persisted desired lease and the App Group snapshot aligned with
/// the active identity, joined channels, and mute state. This is desired client
/// policy only. Relay-accepted authority is introduced by lease publication.
final pushSubscriptionSyncProvider = FutureProvider.autoDispose<void>((
  ref,
) async {
  try {
    if (ref.watch(authProvider).value?.status != AuthStatus.authenticated) {
      return;
    }
    final active = ref.watch(activeCommunityProvider).value;
    if (active == null ||
        !active.pushNotificationsEnabled ||
        ref.watch(currentRelayPushDescriptorProvider).value == null) {
      return;
    }
    final channels = ref.watch(channelsProvider).value;
    final mutes = ref.watch(channelMutesProvider);
    if (channels == null || !mutes.isReady) {
      return;
    }

    final agentKeys =
        ref.watch(notificationAgentKeysProvider).value ??
        const NotificationAgentKeys();
    final subscriptions = desiredBuzzPushSubscriptions(
      community: active,
      channels: channels,
      explicitLevels: explicitChannelLevels(mutes.store),
      agentKeys: agentKeys,
    );
    if (subscriptions == null) return;
    await ref
        .read(communityListProvider.notifier)
        .updateDesiredPushSubscriptions(active.id, subscriptions);
  } catch (error, stack) {
    reportPushSetupError('subscription synchronization', error, stack);
    rethrow;
  }
}, retry: pushSetupRetry);

List<BuzzPushSubscription>? desiredBuzzPushSubscriptions({
  required Community community,
  required Iterable<Channel> channels,
  required Map<String, ChannelNotificationLevel> explicitLevels,
  NotificationAgentKeys agentKeys = const NotificationAgentKeys(),
}) {
  final pubkey = community.pubkey ?? pubkeyFromNsec(community.nsec);
  if (pubkey == null || pubkey.isEmpty) return null;
  final subscribed = [
    for (final channel in channels)
      if (channel.isMember && !channel.isArchived) channel,
  ];
  final muted = <String>[];
  final mentionsOnly = <String>[];
  final loud = <String>[];
  for (final channel in subscribed) {
    final explicit = explicitLevels[channel.id];
    final level =
        explicit ?? defaultChannelNotificationLevel(channel, agentKeys);
    final isDm = channel.channelType == 'dm';
    switch (level) {
      case ChannelNotificationLevel.nothing:
        muted.add(channel.id);
      case ChannelNotificationLevel.mentions when !isDm:
        mentionsOnly.add(channel.id);
      case _ when isDm || explicit != null:
        loud.add(channel.id);
      case _:
        break;
    }
  }
  return buildDesiredBuzzPushSubscriptions(
    myPubkey: pubkey,
    channelIds: [for (final channel in subscribed) channel.id],
    mutedChannelIds: muted,
    mentionsOnlyChannelIds: mentionsOnly,
    loudChannelIds: loud,
    quietAuthorPubkeys: agentKeys.botPubkeys,
  );
}
