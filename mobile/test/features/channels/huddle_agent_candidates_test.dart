import 'package:flutter_test/flutter_test.dart';
import 'package:buzz/features/channels/channel_detail_page.dart';
import 'package:buzz/features/channels/channel_management_provider.dart';
import 'package:buzz/shared/mentions/agent_identity_provider.dart';
import 'package:buzz/shared/profile/user_profile.dart';

void main() {
  test('Huddle offers verified channel agents with a member role', () {
    final joinedAt = DateTime.utc(2026);
    final agents = huddleAgentCandidates(
      members: [
        ChannelMember(pubkey: 'hermes', role: 'member', joinedAt: joinedAt),
        ChannelMember(pubkey: 'human', role: 'member', joinedAt: joinedAt),
        ChannelMember(pubkey: 'bot', role: 'bot', joinedAt: joinedAt),
      ],
      profiles: const {
        'hermes': UserProfile(
          pubkey: 'hermes',
          displayName: 'Hermes',
          ownerPubkey: 'owner',
        ),
        'human': UserProfile(pubkey: 'human'),
      },
      directory: const <AgentDirectoryEntry>[],
      channelId: 'channel',
    );

    expect(agents.map((agent) => agent.pubkey), ['hermes', 'bot']);
    expect(agents.first.displayName, 'Hermes');
  });
}
