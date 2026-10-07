import 'package:buzz/features/channels/channel.dart';
import 'package:buzz/features/channels/channels_provider.dart';
import 'package:buzz/features/channels/message_content.dart';
import 'package:buzz/shared/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Channels extends ChannelsNotifier {
  _Channels(this.channels);

  final List<Channel> channels;

  @override
  Future<List<Channel>> build() async => channels;
}

Channel _channel(String id, String type) => Channel(
  id: id,
  name: id,
  channelType: type,
  visibility: 'open',
  description: '',
  createdBy: 'creator',
  createdAt: DateTime(2026),
  memberCount: 3,
  isMember: true,
);

void main() {
  final zeus = 'a' * 64;
  final argus = 'b' * 64;

  Future<void> pump(WidgetTester tester, String channelId) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          channelsProvider.overrideWith(
            () => _Channels([_channel('ops', 'stream'), _channel('dm', 'dm')]),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: MessageNotifiedLine(
              content: 'Argus: please supply fresh evidence',
              tags: [
                ['p', argus],
                ['p', zeus],
              ],
              senderPubkey: zeus,
              channelId: channelId,
              mentionNames: {zeus: 'Zeus', argus: 'Argus'},
              agentMentionPubkeys: {argus},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows hidden recipients but not the sender', (tester) async {
    await pump(tester, 'ops');
    expect(find.text('Notified:'), findsOneWidget);
    expect(find.text('Argus'), findsOneWidget);
    expect(find.text('Zeus'), findsNothing);
  });

  testWidgets('stays hidden in direct messages', (tester) async {
    await pump(tester, 'dm');
    expect(find.text('Notified:'), findsNothing);
  });
}
