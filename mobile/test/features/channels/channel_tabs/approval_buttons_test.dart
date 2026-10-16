import 'package:buzz/features/channels/channel_tabs/approval_buttons.dart';
import 'package:buzz/features/channels/timeline_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('approve and deny send the agreed emoji', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApprovalButtons(
            reactions: const [],
            onReact: (emoji) async => sent.add(emoji),
          ),
        ),
      ),
    );
    await tester.tap(find.text('✅ Approve'));
    await tester.tap(find.text('❌ Deny'));
    expect(sent, ['✅', '❌']);
  });

  testWidgets('a decided approval shows the decision', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApprovalButtons(
            reactions: const [
              TimelineReaction(
                emoji: '❌',
                count: 1,
                reactedByCurrentUser: true,
                userPubkeys: [],
              ),
            ],
            onReact: (_) async {},
          ),
        ),
      ),
    );
    expect(find.text('You denied'), findsOneWidget);
    expect(find.text('✅ Approve'), findsNothing);
  });
}
