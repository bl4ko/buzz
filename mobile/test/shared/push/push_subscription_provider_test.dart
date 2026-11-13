import 'package:buzz/features/channels/channel.dart';
import 'package:buzz/features/channels/channel_mutes/channel_mutes_storage.dart';
import 'package:buzz/features/channels/channel_mutes/channel_notification_levels.dart';
import 'package:buzz/shared/community/community.dart';
import 'package:buzz/shared/push/push_subscription.dart';
import 'package:buzz/shared/push/push_subscription_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nostr/nostr.dart' as nostr;

void main() {
  const activeID = '123e4567-e89b-42d3-a456-426614174000';
  const archivedID = '123e4567-e89b-42d3-a456-426614174001';
  const nonMemberID = '123e4567-e89b-42d3-a456-426614174002';

  test('includes joined streams and DMs without an explicit mention', () {
    final subscriptions = desiredBuzzPushSubscriptions(
      community: Community.create(
        name: 'Team',
        relayUrl: 'https://relay.example.com',
        nsec: nostr.Keys.generate().nsec,
      ),
      channels: [
        channel(activeID, type: 'stream'),
        channel(archivedID),
        channel(nonMemberID, isMember: false, type: 'stream'),
      ],
      explicitLevels: const {},
    );

    expect(subscriptions, hasLength(2));
    expect(subscriptions!.last.filter.hTags, [activeID, archivedID]);
    expect(subscriptions.last.filter.pTags, isNull);
    expect(subscriptions.last.filter.kinds, [9]);
    expect(
      subscriptions.last.ignore.first.authors,
      subscriptions.first.filter.pTags,
    );
  });

  test(
    'derives desired subscriptions from nsec, membership, and mute state',
    () {
      final nsec = nostr.Keys.generate().nsec;
      final subscriptions = desiredBuzzPushSubscriptions(
        community: Community.create(
          name: 'Team',
          relayUrl: 'https://relay.example.com',
          nsec: nsec,
        ),
        channels: [
          channel(activeID, type: 'stream'),
          channel(archivedID, archived: true, type: 'stream'),
          channel(nonMemberID, isMember: false, type: 'stream'),
        ],
        explicitLevels: const {
          activeID: ChannelNotificationLevel.nothing,
          archivedID: ChannelNotificationLevel.nothing,
        },
      );

      expect(subscriptions, isNotNull);
      expect(subscriptions, hasLength(1));
      expect(subscriptions!.single.filter.pTags, hasLength(1));
      expect(subscriptions.single.ignore, hasLength(2));
      expect(subscriptions.single.ignore.first.kinds, buzzPushRenderableKinds);
      expect(subscriptions.single.ignore.last.hTags, [activeID]);
    },
  );

  group('notification levels', () {
    const workspaceID = '4801fa7c-c7a0-526a-8ed8-39623259952e';
    const alertsID = '22a08d0a-02dd-49dc-8510-2d2b2eb47bbd';
    const quietID = '123e4567-e89b-42d3-a456-426614174003';
    const dmID = '123e4567-e89b-42d3-a456-426614174004';
    final bot = 'b' * 64;
    final keys = NotificationAgentKeys(
      botPubkeys: {bot},
      agentChannelIds: {workspaceID},
    );
    List<BuzzPushSubscription> lease(
      Map<String, ChannelNotificationLevel> explicit,
    ) => desiredBuzzPushSubscriptions(
      community: Community.create(
        name: 'Team',
        relayUrl: 'https://relay.example.com',
        nsec: nostr.Keys.generate().nsec,
      ),
      channels: [
        channel(workspaceID, type: 'stream'),
        channel(alertsID, type: 'stream'),
        channel(quietID, type: 'stream'),
        channel(dmID),
      ],
      explicitLevels: explicit,
      agentKeys: keys,
    )!;

    test('agent channels get mentions only; bot posts are quiet elsewhere', () {
      final subscriptions = lease(const {});
      expect(subscriptions, hasLength(3));
      final mentions = subscriptions.first;
      expect(mentions.filter.hTags, isNull);
      expect(
        mentions.ignore.expand((f) => f.authors ?? []),
        isNot(contains(bot)),
      );
      final loud = subscriptions[1];
      expect(loud.filter.hTags, [dmID]);
      expect(loud.ignore.expand((f) => f.authors ?? []), isNot(contains(bot)));
      final quiet = subscriptions[2];
      expect(quiet.filter.hTags, [alertsID, quietID]..sort());
      expect(quiet.ignore.last.authors, [bot]);
      expect(quiet.ignore.last.kinds, [9]);
    });

    test('explicit levels override the defaults', () {
      final subscriptions = lease(const {
        workspaceID: ChannelNotificationLevel.all,
        alertsID: ChannelNotificationLevel.mentions,
        quietID: ChannelNotificationLevel.nothing,
      });
      expect(subscriptions, hasLength(2));
      expect(subscriptions.first.ignore.last.hTags, [quietID]);
      expect(subscriptions.last.filter.hTags, [dmID, workspaceID]..sort());
      expect(
        subscriptions.last.ignore.expand((f) => f.authors ?? []),
        isNot(contains(bot)),
      );
    });
  });

  test('returns no desired subscriptions without a signing identity', () {
    final subscriptions = desiredBuzzPushSubscriptions(
      community: Community.create(
        name: 'Team',
        relayUrl: 'https://relay.example.com',
      ),
      channels: [channel(activeID)],
      explicitLevels: const {},
    );

    expect(subscriptions, isNull);
  });
}

Channel channel(
  String id, {
  bool isMember = true,
  bool archived = false,
  String type = 'dm',
}) => Channel(
  id: id,
  name: id,
  channelType: type,
  visibility: 'open',
  description: '',
  createdBy: 'author',
  createdAt: DateTime(2026),
  memberCount: 1,
  isMember: isMember,
  archivedAt: archived ? DateTime(2026) : null,
);
