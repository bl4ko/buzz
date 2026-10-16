import 'dart:async';
import 'dart:math' as math;

import 'package:buzz/features/channels/channel_tabs/approval_buttons.dart';
import 'package:buzz/features/channels/channel_tabs/thread_status.dart';
import 'package:buzz/features/channels/timeline_message.dart';
import 'package:buzz/shared/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('approve and deny send the agreed emoji', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ApprovalButtons(
            askEventId: 'a',
            reactions: const [],
            onReact: (emoji) async => sent.add(emoji),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Approve'));
    await tester.tap(find.text('Deny'));
    expect(sent, ['✅', '❌']);
  });

  testWidgets('a decided approval shows the decision', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
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
    expect(find.text('Approve'), findsNothing);
  });

  Widget host(String askId, Future<void> Function(String) onReact) =>
      MaterialApp(
        theme: AppTheme.light(),
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
    await tester.tap(find.text('Approve'));
    await tester.pump();
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    await tester.pumpWidget(host('b', (_) async {}));
    expect(find.text('Approve'), findsOneWidget);
    await tester.tap(find.text('Deny'));
    await tester.pump();
    expect(find.text('Denied'), findsOneWidget);
  });

  testWidgets('a failed publish shows an error and keeps the buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      host('a', (_) async => throw Exception('rejected')),
    );
    await tester.tap(find.text('Approve'));
    await tester.pump();
    expect(find.text("Couldn't send the decision"), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Approved'), findsNothing);
  });

  testWidgets('both buttons are disabled while a send is pending', (
    tester,
  ) async {
    final pending = Completer<void>();
    final sent = <String>[];
    await tester.pumpWidget(
      host('a', (emoji) {
        sent.add(emoji);
        return pending.future;
      }),
    );
    await tester.tap(find.text('Approve'));
    await tester.pump();
    await tester.tap(find.text('Deny'));
    await tester.pump();
    expect(sent, ['✅']);
    pending.complete();
    await tester.pump();
    expect(find.text('Approved'), findsOneWidget);
  });

  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  for (final (name, theme) in [
    ('light', AppTheme.light()),
    ('dark', AppTheme.dark()),
  ]) {
    for (final decision in OwnerDecision.values) {
      testWidgets('the ${decision.name} chip text is readable in $name', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(body: TaskDecisionChip(decision: decision)),
          ),
        );
        final box = tester.widget<Container>(
          find.descendant(
            of: find.byType(TaskDecisionChip),
            matching: find.byType(Container),
          ),
        );
        final tint = (box.decoration! as BoxDecoration).color!;
        final text = tester.widget<Text>(find.byType(Text));
        final background = Color.alphaBlend(tint, theme.colorScheme.surface);
        expect(
          contrast(text.style!.color!, background),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  }
}
