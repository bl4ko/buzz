part of '../channel_detail_page_test.dart';

void initialTabTests() {
  final task = ThreadTask(
    rootId: 'aa' * 32,
    channelId: _channelId,
    status: TaskStatus.inProgress,
    title: 'Rotate keys',
    ask: null,
    author: 'bb' * 32,
    createdAt: 1,
    eventId: 'cc' * 32,
  );
  final tasks = ChannelTasksState({task.rootId: task});

  Finder tabBody(String selected) => find.byWidgetPredicate(
    (widget) => widget is ChannelTabBody && widget.selected == selected,
  );

  testWidgets('channel page starts on initial tab', (tester) async {
    await tester.pumpWidget(
      _buildTestable(
        messages: const [],
        tasks: tasks,
        home: ChannelDetailPage(channel: _testChannel, initialTab: 'tasks'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tabBody('tasks'), findsOneWidget);
  });

  testWidgets('channel page starts on messages without an initial tab', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildTestable(messages: const [], tasks: tasks),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ChannelTabBody), findsNothing);
  });
}
