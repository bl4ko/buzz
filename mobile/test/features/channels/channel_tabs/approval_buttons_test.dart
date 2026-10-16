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
            askEventId: 'a',
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
            askEventId: 'a',
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

  Widget host(String askId, Future<void> Function(String) onReact) =>
      MaterialApp(
        home: Scaffold(
          body: ApprovalButtons(
            askEventId: askId,
            reactions: const [],
            onReact: onReact,
          ),
        ),
      );

  testWidgets('a sent decision shows its label until a new ask arrives', (
    tester,
  ) async {
    await tester.pumpWidget(host('a', (_) async {}));
    await tester.tap(find.text('✅ Approve'));
    await tester.pump();
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('✅ Approve'), findsNothing);
    await tester.pumpWidget(host('b', (_) async {}));
    expect(find.text('✅ Approve'), findsOneWidget);
    await tester.tap(find.text('❌ Deny'));
    await tester.pump();
    expect(find.text('Denied'), findsOneWidget);
  });

  testWidgets('a failed publish shows an error and keeps the buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      host('a', (_) async => throw Exception('rejected')),
    );
    await tester.tap(find.text('✅ Approve'));
    await tester.pump();
    expect(find.text("Couldn't send the decision"), findsOneWidget);
    expect(find.text('✅ Approve'), findsOneWidget);
    expect(find.text('Approved'), findsNothing);
  });
}
