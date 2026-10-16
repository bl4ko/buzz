import 'package:buzz/features/channels/channel_tabs/channel_tasks_provider.dart';
import 'package:buzz/features/channels/channel_tabs/channel_tasks_view.dart';
import 'package:buzz/features/channels/channel_tabs/thread_status.dart';
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
    ])
      t.rootId: t,
  });

  Future<List<String>> pump(
    WidgetTester tester, {
    required bool canSetStatus,
  }) async {
    final log = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChannelTasksView(
            state: state,
            canSetStatus: canSetStatus,
            onReact: (eventId, emoji) async =>
                log.add('react:$emoji:${eventId[0]}'),
            onDone: (t) async => log.add('done:${t.rootId[0]}'),
            onOpenThread: (rootId) => log.add('open:${rootId[0]}'),
          ),
        ),
      ),
    );
    return log;
  }

  testWidgets('groups, approve, deny, done, open, and collapsed done', (
    tester,
  ) async {
    final log = await pump(tester, canSetStatus: true);
    expect(find.text('Needs you'), findsOneWidget);
    expect(find.text('Merge PR 7?'), findsOneWidget);
    expect(find.text('Task 4'), findsNothing);
    await tester.tap(find.text('✅'));
    await tester.tap(find.text('❌'));
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Task 1'),
        matching: find.text('Done'),
      ),
    );
    await tester.tap(find.text('Task 2'));
    await tester.tap(find.text('Done (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Task 4'), findsOneWidget);
    expect(log, ['react:✅:b', 'react:❌:b', 'done:1', 'open:2']);
  });

  testWidgets('no Done, Approve, or Deny buttons without owner rights', (
    tester,
  ) async {
    await pump(tester, canSetStatus: false);
    expect(find.text('Done'), findsNothing);
    expect(find.text('✅'), findsNothing);
    expect(find.text('❌'), findsNothing);
    expect(find.text('Merge PR 7?'), findsOneWidget);
  });

  Widget host(
    ChannelTasksState tasks,
    Future<void> Function(String, String) onReact,
  ) => MaterialApp(
    home: Scaffold(
      body: ChannelTasksView(
        state: tasks,
        canSetStatus: true,
        onReact: onReact,
        onDone: (_) async {},
        onOpenThread: (_) {},
      ),
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

  testWidgets('a sent decision shows its label until a new ask event arrives', (
    tester,
  ) async {
    await tester.pumpWidget(host(withAsk('b' * 64), (_, _) async {}));
    await tester.tap(find.text('✅'));
    await tester.pump();
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('✅'), findsNothing);
    await tester.pumpWidget(host(withAsk('c' * 64), (_, _) async {}));
    expect(find.text('✅'), findsOneWidget);
    expect(find.text('Approved'), findsNothing);
    await tester.tap(find.text('❌'));
    await tester.pump();
    expect(find.text('Denied'), findsOneWidget);
  });

  testWidgets('a failed reaction shows an error and keeps the buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(withAsk('b' * 64), (_, _) async => throw Exception('rejected')),
    );
    await tester.tap(find.text('✅'));
    await tester.pump();
    expect(find.text("Couldn't send approval"), findsOneWidget);
    expect(find.text('✅'), findsOneWidget);
  });
}
