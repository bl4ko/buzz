import 'dart:async';

import 'package:buzz/features/channels/channel_tabs/approval_buttons.dart';
import 'package:buzz/features/channels/channel_tabs/channel_tasks_provider.dart';
import 'package:buzz/features/channels/channel_tabs/channel_tasks_view.dart';
import 'package:buzz/features/channels/channel_tabs/thread_status.dart';
import 'package:buzz/shared/theme/buzz_icons.dart';
import 'package:buzz/shared/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('a decided row moves to In progress with a chip and no buttons', (
    tester,
  ) async {
    final t = task('1', TaskStatus.awaitingOwner, ask: ask);
    final decided = ChannelTasksState(
      {t.rootId: t},
      {ask.eventId: OwnerDecision.deny},
    );
    await pump(tester, canSetStatus: true, tasks: decided);
    expect(decided.awaitingCount, 0);
    expect(find.textContaining('Needs you'), findsNothing);
    expect(find.text('In progress · 1'), findsOneWidget);
    expect(inRow('Task 1', find.byType(TaskDecisionChip)), findsOneWidget);
    expect(inRow('Task 1', find.text('Denied')), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Deny'), findsNothing);
    expect(inRow('Task 1', find.byTooltip('Mark Task 1 done')), findsOneWidget);
  });

  testWidgets('mark done, open thread, and the collapsible Done group', (
    tester,
  ) async {
    final log = await pump(tester, canSetStatus: true);
    await tester.tap(inRow('Task 1', find.byTooltip('Mark Task 1 done')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Task 2'));
    expect(find.text('Task 4'), findsNothing);
    expect(find.byIcon(BuzzIcons.chevronRight), findsOneWidget);
    await tester.tap(find.text('Done · 2'));
    await tester.pumpAndSettle();
    expect(find.text('Task 4'), findsOneWidget);
    expect(find.text('Task 5'), findsOneWidget);
    expect(find.byIcon(BuzzIcons.chevronDown), findsOneWidget);
    expect(inRow('Task 4', find.byTooltip('Mark Task 4 done')), findsNothing);
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
        label: 'Done, 2',
        hint: 'Show done tasks',
        isHeader: true,
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
    expect(find.byType(IconButton), findsNothing);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Deny'), findsNothing);
    expect(find.text('Merge PR 7?'), findsOneWidget);
  });

  testWidgets('titles wrap at the largest text size and asks keep two lines', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    const title = 'Rotate the staging relay key';
    const long = ThreadTask(
      rootId: 'a',
      channelId: 'c',
      status: TaskStatus.awaitingOwner,
      title: title,
      ask: ThreadTaskAsk(text: 'Rotate it now?', eventId: 'b'),
      author: 'e',
      createdAt: 10,
      eventId: 'a',
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(402, 874),
          textScaler: TextScaler.linear(3.12),
        ),
        child: app(
          ChannelTasksView(
            state: const ChannelTasksState(
              {'a': long},
              {'b': OwnerDecision.approve},
            ),
            canSetStatus: true,
            onReact: (_, _) async {},
            onDone: (_) async {},
            onOpenThread: (_) {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final paragraph = tester.renderObject<RenderParagraph>(find.text(title));
    expect(paragraph.didExceedMaxLines, isFalse);
    final titleRect = tester.getRect(find.text(title));
    final chipRect = tester.getRect(find.byType(TaskDecisionChip));
    expect(titleRect.overlaps(chipRect), isFalse);
    expect(chipRect.right, lessThanOrEqualTo(402));
    expect(
      tester.getRect(find.byTooltip('Mark $title done')).overlaps(titleRect),
      isFalse,
    );

    final askRow = task(
      '1',
      TaskStatus.awaitingOwner,
      ask: ThreadTaskAsk(text: 'Ask ' * 80, eventId: 'b' * 64),
    );
    await pump(
      tester,
      canSetStatus: true,
      tasks: ChannelTasksState({askRow.rootId: askRow}),
    );
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
    await tester.pump(const Duration(seconds: 1));
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

  testWidgets('actions and headers name the task for VoiceOver', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, canSetStatus: true);
    for (final title in ['Task 1', 'Task 2', 'Task 3']) {
      expect(
        tester.getSemantics(find.byTooltip('Mark $title done')).tooltip,
        'Mark $title done',
      );
    }
    expect(find.bySemanticsLabel('Approve Task 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Deny Task 1'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Needs you, 1')),
      isSemantics(label: 'Needs you, 1', isHeader: true),
    );
    semantics.dispose();
  });

  testWidgets('Mark done is disabled until the publish returns', (
    tester,
  ) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      app(
        ChannelTasksView(
          state: withAsk('b' * 64),
          canSetStatus: true,
          onReact: (_, _) async {},
          onDone: (_) {
            calls++;
            return pending.future;
          },
          onOpenThread: (_) {},
        ),
      ),
    );
    final button = find.byTooltip('Mark Task 1 done');
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    expect(calls, 1);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(of: button, matching: find.byType(IconButton)),
          )
          .onPressed,
      isNull,
    );
    pending.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(button);
    await tester.pump();
    expect(calls, 2);
  });

  testWidgets('a fast second tap cannot decide or open the row that moves up', (
    tester,
  ) async {
    final first = task(
      '1',
      TaskStatus.awaitingOwner,
      ask: ThreadTaskAsk(text: 'First?', eventId: 'b' * 64),
    );
    final second = ThreadTask(
      rootId: '2' * 64,
      channelId: 'c',
      status: TaskStatus.awaitingOwner,
      title: 'Task 2',
      ask: ThreadTaskAsk(text: 'Second?', eventId: 'c' * 64),
      author: 'e' * 64,
      createdAt: 9,
      eventId: '2' * 64,
    );
    var decisions = <String, OwnerDecision>{};
    final log = <String>[];
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => app(
          ChannelTasksView(
            state: ChannelTasksState({
              first.rootId: first,
              second.rootId: second,
            }, decisions),
            canSetStatus: true,
            onReact: (eventId, emoji) async {
              log.add('react:$emoji:${eventId[0]}');
              setState(
                () => decisions = {
                  ...decisions,
                  eventId: emoji == approveEmoji
                      ? OwnerDecision.approve
                      : OwnerDecision.deny,
                },
              );
            },
            onDone: (_) async {},
            onOpenThread: (rootId) => log.add('open:${rootId[0]}'),
          ),
        ),
      ),
    );
    final approve = tester.getCenter(find.text('Approve').first);
    final title = tester.getCenter(find.text('Task 1'));
    await tester.tapAt(approve);
    await tester.pump();
    expect(find.text('Needs you · 1'), findsOneWidget);
    expect(tester.getCenter(find.text('Approve')), approve);
    await tester.tapAt(approve);
    await tester.tapAt(title);
    await tester.pump();
    expect(log, ['react:✅:b']);
    expect(decisions.keys, ['b' * 64]);

    await tester.pump(const Duration(seconds: 1));
    await tester.tapAt(approve);
    await tester.pump();
    expect(log, ['react:✅:b', 'react:✅:c']);
  });

  testWidgets('a fast second tap on Done cannot close the row that moves up', (
    tester,
  ) async {
    ThreadTask open(String id, int createdAt, [TaskStatus? status]) =>
        ThreadTask(
          rootId: id * 64,
          channelId: 'c',
          status: status ?? TaskStatus.inProgress,
          title: 'Task $id',
          ask: null,
          author: 'e' * 64,
          createdAt: createdAt,
          eventId: id * 64,
        );
    var tasks = {
      for (final t in [open('1', 10), open('2', 9)]) t.rootId: t,
    };
    final log = <String>[];
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => app(
          ChannelTasksView(
            state: ChannelTasksState(tasks),
            canSetStatus: true,
            onReact: (_, _) async {},
            onDone: (t) async {
              log.add('done:${t.rootId[0]}');
              setState(
                () => tasks = {
                  ...tasks,
                  t.rootId: open(t.rootId[0], t.createdAt, TaskStatus.done),
                },
              );
            },
            onOpenThread: (rootId) => log.add('open:${rootId[0]}'),
          ),
        ),
      ),
    );
    final done = tester.getCenter(find.byTooltip('Mark Task 1 done'));
    await tester.tapAt(done);
    await tester.pump();
    expect(tester.getCenter(find.byTooltip('Mark Task 2 done')), done);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(done);
    await tester.pump();
    expect(log, ['done:1']);

    await tester.pump(const Duration(seconds: 1));
    await tester.tapAt(done);
    await tester.pump();
    expect(log, ['done:1', 'done:2']);
  });
}
