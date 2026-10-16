part of '../channel_detail_page_test.dart';

void channelTabComposerTests() {
  final tasks = ChannelTasksState({
    'a' * 64: ThreadTask(
      rootId: 'a' * 64,
      channelId: _channelId,
      status: TaskStatus.inProgress,
      title: 'Rotate relay key',
      ask: null,
      author: 'e' * 64,
      createdAt: 10,
      eventId: 'f' * 64,
    ),
  });
  List<NostrEvent> messages(int count) => [
    for (var i = 0; i < count; i++)
      _textMsg(
        id: 'm$i',
        pubkey: 'bob',
        content: 'Timeline message $i',
        createdAt: 1000 + i,
      ),
  ];
  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  group('Channel tab body and composer', () {
    testWidgets('composer leaves semantics, paint and hit testing', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _buildTestable(messages: messages(3), tasks: tasks),
      );
      await tester.pumpAndSettle();
      expect(find.semantics.byLabel(RegExp('Message #general')), findsWidgets);

      await openTab(tester, 'Tasks');

      expect(find.text('Rotate relay key'), findsOneWidget);
      expect(find.semantics.byLabel(RegExp('Message #general')), findsNothing);
      expect(find.semantics.byLabel(RegExp('Timeline message')), findsNothing);
      expect(find.byKey(const ValueKey('composer-surface')), findsNothing);
      expect(find.byType(ComposeBar), findsNothing);
      expect(find.byType(ComposeBar, skipOffstage: false), findsOneWidget);
      expect(find.text('Message #general').hitTestable(), findsNothing);

      await openTab(tester, 'Messages');

      expect(find.byKey(const ValueKey('composer-surface')), findsOneWidget);
      expect(find.semantics.byLabel(RegExp('Message #general')), findsWidgets);
      expect(find.semantics.byLabel(RegExp('Timeline message')), findsWidgets);
      semantics.dispose();
    });

    testWidgets('iOS composer glass is not painted under the tab body', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.pumpWidget(
        _buildTestable(messages: messages(3), tasks: tasks),
      );
      await tester.pumpAndSettle();
      final glass = find.byKey(
        const ValueKey('composer-ios-concentric-surface'),
      );
      expect(glass, findsOneWidget);

      await openTab(tester, 'Tasks');

      expect(glass, findsNothing);
      expect(
        find.byKey(
          const ValueKey('composer-ios-concentric-surface'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      await openTab(tester, 'Messages');

      expect(glass, findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    for (final focused in [true, false]) {
      testWidgets('draft and focus=$focused survive Tasks and back', (
        tester,
      ) async {
        await tester.pumpWidget(
          _buildTestable(messages: messages(3), tasks: tasks),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Message #general'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'half-written reply');
        await tester.pumpAndSettle();
        final field = find.byType(EditableText, skipOffstage: false);
        final focusNode = tester.widget<EditableText>(field).focusNode;
        if (!focused) {
          focusNode.unfocus();
          await tester.pumpAndSettle();
        }

        await openTab(tester, 'Tasks');
        expect(find.text('half-written reply'), findsNothing);
        expect(focusNode.hasFocus, isFalse);
        await openTab(tester, 'Messages');

        expect(find.text('half-written reply'), findsOneWidget);
        expect(focusNode.hasFocus, focused);
      });
    }

    testWidgets('opening a task leaves the hidden channel composer unfocused', (
      tester,
    ) async {
      final threadTasks = ChannelTasksState({
        'm0': ThreadTask(
          rootId: 'm0',
          channelId: _channelId,
          status: TaskStatus.inProgress,
          title: 'Rotate relay key',
          ask: null,
          author: 'e' * 64,
          createdAt: 10,
          eventId: 'f' * 64,
        ),
      });
      await tester.pumpWidget(
        _buildTestable(messages: messages(3), tasks: threadTasks),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Message #general'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'half-written reply');
      await tester.pumpAndSettle();
      final channelFocus = tester
          .widget<EditableText>(find.byType(EditableText, skipOffstage: false))
          .focusNode;
      expect(channelFocus.hasFocus, isTrue);

      await openTab(tester, 'Tasks');
      await tester.tap(find.text('Rotate relay key'));
      await tester.pumpAndSettle();

      expect(find.byType(ThreadDetailPage), findsOneWidget);
      expect(channelFocus.hasFocus, isFalse);

      await tester.tap(find.text('Reply in thread…').hitTestable());
      await tester.pumpAndSettle();
      tester.testTextInput.enterText('thread answer');
      await tester.pumpAndSettle();

      expect(channelFocus.hasFocus, isFalse);
      expect(
        find.textContaining('thread answer', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('thread answer'), findsOneWidget);
      expect(
        find.text('half-written reply', skipOffstage: false),
        findsWidgets,
      );
    });

    testWidgets('timeline keeps its scroll position after Tasks', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestable(messages: messages(60), tasks: tasks),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.text('Timeline message 59'), const Offset(0, 900));
      await tester.pumpAndSettle();
      final anchor = [
        for (var i = 0; i < 59; i++) find.text('Timeline message $i'),
      ].firstWhere((finder) => finder.evaluate().isNotEmpty);
      expect(find.text('Timeline message 59').hitTestable(), findsNothing);
      final before = tester.getTopLeft(anchor);

      await openTab(tester, 'Tasks');
      await openTab(tester, 'Messages');

      expect(tester.getTopLeft(anchor), before);
    });
  });
}
