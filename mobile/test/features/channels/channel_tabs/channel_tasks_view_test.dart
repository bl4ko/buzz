import 'dart:async';

import 'package:buzz/features/channels/channel_tabs/approval_buttons.dart';
import 'package:buzz/features/channels/channel_tabs/channel_tasks_provider.dart';
import 'package:buzz/features/channels/channel_tabs/channel_tasks_view.dart';
import 'package:buzz/features/channels/channel_tabs/thread_status.dart';
import 'package:buzz/shared/theme/buzz_icons.dart';
import 'package:buzz/shared/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ThreadTask task(String id, TaskStatus status, {ThreadTaskAsk? ask}) =>
    ThreadTask(
      rootId: id * 64,
      channelId: 'c',
      status: status,
      title: 'Task $id',
      ask: ask,
      author: 'e' * 64,
      createdAt: 10,
      eventId: id * 64,
    );

void main() {
  final ask = ThreadTaskAsk(text: 'Merge PR 7?', eventId: 'b' * 64);
  final state = ChannelTasksState({
    for (final t in [
      task('1', TaskStatus.awaitingOwner, ask: ask),
      task('2', TaskStatus.inProgress),
      task('3', TaskStatus.blocked),
      task('4', TaskStatus.done),
      task('5', TaskStatus.done),
    ])
      t.rootId: t,
  });

  Widget app(Widget body) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: body),
  );

  Future<List<String>> pump(
    WidgetTester tester, {
    required bool canSetStatus,
    ChannelTasksState? tasks,
  }) async {
    final log = <String>[];
    await tester.pumpWidget(
      app(
        ChannelTasksView(
          state: tasks ?? state,
          canSetStatus: canSetStatus,
          onReact: (eventId, emoji) async =>
              log.add('react:$emoji:${eventId[0]}'),
          onDone: (t) async => log.add('done:${t.rootId[0]}'),
          onOpenThread: (rootId) => log.add('open:${rootId[0]}'),
        ),
      ),
    );
    return log;
  }

  Finder inRow(String title, Finder matching) => find.descendant(
    of: find.byKey(Key('task-row-${title[title.length - 1] * 64}')),
    matching: matching,
  );

  testWidgets('section headers show counts and the list starts at the top', (
    tester,
  ) async {
    await pump(tester, canSetStatus: true);
    expect(find.text('Needs you · 1'), findsOneWidget);
    expect(find.text('In progress · 1'), findsOneWidget);
    expect(find.text('Blocked · 1'), findsOneWidget);
    expect(find.text('Done · 2'), findsOneWidget);
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.padding?.resolve(TextDirection.ltr).top, lessThan(Grid.xs));
    expect(
      tester.getTopLeft(find.text('Needs you · 1')).dy,
      lessThan(Grid.sm * 2),
    );
  });

  testWidgets('an undecided ask shows Approve and Deny and they send', (
    tester,
  ) async {
    final log = await pump(tester, canSetStatus: true);
    expect(inRow('Task 1', find.text('Merge PR 7?')), findsOneWidget);
    expect(inRow('Task 1', find.byType(FilledButton)), findsOneWidget);
    expect(inRow('Task 1', find.byType(OutlinedButton)), findsOneWidget);
    expect(find.byType(TaskDecisionChip), findsNothing);
    await tester.tap(find.text('Approve'));
    await tester.pump();
    expect(log, ['react:✅:b']);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
  });

  testWidgets('a decided row stays in Needs you with a chip and no buttons', (
    tester,
  ) async {
    final t = task('1', TaskStatus.awaitingOwner, ask: ask);
    await pump(
      tester,
      canSetStatus: true,
      tasks: ChannelTasksState(
        {t.rootId: t},
        {ask.eventId: OwnerDecision.deny},
      ),
    );
    expect(find.text('Needs you · 1'), findsOneWidget);
    expect(inRow('Task 1', find.byType(TaskDecisionChip)), findsOneWidget);
    expect(inRow('Task 1', find.text('Denied')), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Deny'), findsNothing);
    expect(inRow('Task 1', find.byTooltip('Mark done')), findsOneWidget);
  });

  testWidgets('mark done, open thread, and the collapsible Done group', (
    tester,
  ) async {
    final log = await pump(tester, canSetStatus: true);
    await tester.tap(inRow('Task 1', find.byTooltip('Mark done')));
    await tester.pump();
    await tester.tap(find.text('Task 2'));
    expect(find.text('Task 4'), findsNothing);
    expect(find.byIcon(BuzzIcons.chevronRight), findsOneWidget);
    await tester.tap(find.text('Done · 2'));
    await tester.pumpAndSettle();
    expect(find.text('Task 4'), findsOneWidget);
    expect(find.text('Task 5'), findsOneWidget);
    expect(find.byIcon(BuzzIcons.chevronDown), findsOneWidget);
    expect(inRow('Task 4', find.byTooltip('Mark done')), findsNothing);
    await tester.tap(find.text('Done · 2'));
    await tester.pumpAndSettle();
    expect(find.text('Task 4'), findsNothing);
    expect(log, ['done:1', 'open:2']);
  });

  testWidgets('the Done header announces its state', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, canSetStatus: true);
    expect(
      tester.getSemantics(find.byKey(const Key('tasks-done-toggle'))),
      matchesSemantics(
        label: 'Done · 2',
        hint: 'Show done tasks',
        isButton: true,
        hasTapAction: true,
        hasExpandedState: true,
        isExpanded: false,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('no Mark done, Approve, or Deny without owner rights', (
    tester,
  ) async {
    await pump(tester, canSetStatus: false);
    expect(find.byTooltip('Mark done'), findsNothing);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Deny'), findsNothing);
    expect(find.text('Merge PR 7?'), findsOneWidget);
  });

  testWidgets('titles keep one line and asks keep two lines', (tester) async {
    final long = task(
      '1',
      TaskStatus.awaitingOwner,
      ask: ThreadTaskAsk(text: 'Ask ' * 80, eventId: 'b' * 64),
    );
    await pump(
      tester,
      canSetStatus: true,
      tasks: ChannelTasksState({long.rootId: long}),
    );
    final title = tester.widget<Text>(find.text('Task 1'));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    final askText = tester.widget<Text>(find.text('Ask ' * 80));
    expect(askText.maxLines, 2);
    expect(askText.overflow, TextOverflow.ellipsis);
  });

  testWidgets('dark theme and large text render without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: ChannelTasksView(
              state: state,
              canSetStatus: true,
              onReact: (_, _) async {},
              onDone: (_) async {},
              onOpenThread: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Approve'), findsOneWidget);
  });

  Widget host(
    ChannelTasksState tasks,
    Future<void> Function(String, String) onReact,
  ) => app(
    ChannelTasksView(
      state: tasks,
      canSetStatus: true,
      onReact: onReact,
      onDone: (_) async {},
      onOpenThread: (_) {},
    ),
  );

  ChannelTasksState withAsk(String eventId) {
    final t = task(
      '1',
      TaskStatus.awaitingOwner,
      ask: ThreadTaskAsk(text: 'Merge PR 7?', eventId: eventId),
    );
    return ChannelTasksState({t.rootId: t});
  }

  testWidgets('a sent decision shows its chip until a new ask event arrives', (
    tester,
  ) async {
    await tester.pumpWidget(host(withAsk('b' * 64), (_, _) async {}));
    await tester.tap(find.text('Approve'));
    await tester.pump();
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    await tester.pumpWidget(host(withAsk('c' * 64), (_, _) async {}));
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Approved'), findsNothing);
    await tester.tap(find.text('Deny'));
    await tester.pump();
    expect(find.text('Denied'), findsOneWidget);
  });

  testWidgets('a failed reaction shows an error and keeps the buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(withAsk('b' * 64), (_, _) async => throw Exception('rejected')),
    );
    await tester.tap(find.text('Approve'));
    await tester.pump();
    expect(find.text("Couldn't send approval"), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
  });

  ChannelTasksState decided(String eventId, OwnerDecision decision) {
    final t = task(
      '1',
      TaskStatus.awaitingOwner,
      ask: ThreadTaskAsk(text: 'Merge PR 7?', eventId: eventId),
    );
    return ChannelTasksState({t.rootId: t}, {eventId: decision});
  }

  testWidgets('the stored reaction wins over the local decision', (
    tester,
  ) async {
    await tester.pumpWidget(host(withAsk('b' * 64), (_, _) async {}));
    await tester.tap(find.text('Approve'));
    await tester.pump();
    expect(find.text('Approved'), findsOneWidget);
    await tester.pumpWidget(
      host(decided('b' * 64, OwnerDecision.deny), (_, _) async {}),
    );
    expect(find.text('Denied'), findsOneWidget);
  });

  testWidgets('both buttons are disabled while a send is pending', (
    tester,
  ) async {
    final pending = Completer<void>();
    final sent = <String>[];
    await tester.pumpWidget(
      host(withAsk('b' * 64), (_, emoji) {
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
}
