import 'package:buzz/features/channels/channel.dart';
import 'package:buzz/features/channels/channel_tabs/channel_tabs_model.dart';
import 'package:buzz/features/channels/channel_tabs/custom_tab_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets('a link value with outer whitespace still renders its button', (
    tester,
  ) async {
    final channel = Channel(
      id: 'c',
      name: 'general',
      channelType: 'stream',
      visibility: 'open',
      description: '',
      createdBy: 'a',
      createdAt: DateTime.utc(2026),
      memberCount: 1,
      isMember: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CustomTabView(
              channel: channel,
              tab: const ChannelTab(
                id: 'g',
                type: 'link',
                title: 'G',
                value: '  https://g.example/x  ',
              ),
              canEditCanvas: false,
              onOpenMessage: (_) {},
              onOpenThread: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Open g.example'), findsOneWidget);
  });
}
