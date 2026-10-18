part of '../channel_detail_page_test.dart';

void headerOpacityTests() {
  testWidgets('iOS channel header hides timeline text under the native bar', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final messenger = tester.binding.defaultBinaryMessenger;
    final mocked = <MethodChannel>[const MethodChannel('buzz/media_upload')];
    messenger.setMockMethodCallHandler(mocked.first, (call) async => false);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final args = call.arguments as Map;
        final view = MethodChannel('${args['viewType']}/${args['id']}');
        mocked.add(view);
        messenger.setMockMethodCallHandler(view, (call) async => null);
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      for (final channel in mocked) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });
    final shot = GlobalKey();
    await tester.pumpWidget(
      _buildTestable(
        messages: [
          for (var i = 0; i < 40; i++)
            _textMsg(
              id: 'm$i',
              pubkey: 'bob',
              content: 'Timeline message $i',
              createdAt: 1000 + i,
            ),
        ],
        tasks: ChannelTasksState({
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
        }),
        home: RepaintBoundary(
          key: shot,
          child: ChannelDetailPage(channel: _testChannel),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bar = tester.getRect(
      find.descendant(
        of: find.byType(FrostedAppBar),
        matching: find.byType(UiKitView),
      ),
    );
    final tabs = tester.getRect(find.byType(ChannelTabRow));
    expect(bar.top, 0);
    expect(tabs.top, closeTo(bar.bottom, 0.01));
    final textUnderBar = find
        .textContaining('Timeline message')
        .evaluate()
        .map((element) => element.renderObject! as RenderBox)
        .any(
          (box) => (box.localToGlobal(Offset.zero) & box.size).overlaps(bar),
        );
    expect(textUnderBar, isTrue);

    final surface = Theme.of(
      tester.element(find.byType(ChannelDetailPage)),
    ).colorScheme.surface;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(shot),
    );
    final pixels = (await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData();
      image.dispose();
      return data!;
    }))!;
    final width = boundary.size.width.toInt();
    Color pixel(int x, int y) {
      final i = (y * width + x) * 4;
      return Color.fromARGB(
        pixels.getUint8(i + 3),
        pixels.getUint8(i),
        pixels.getUint8(i + 1),
        pixels.getUint8(i + 2),
      );
    }

    final leaks = <String>[
      for (var y = 0; y < bar.bottom.floor(); y++)
        for (var x = 0; x < width; x++)
          if (pixel(x, y) != surface) '($x, $y)',
      for (var y = tabs.top.ceil(); y < tabs.bottom.floor() - 1; y++)
        if (pixel(width - 2, y) != surface) '(${width - 2}, $y)',
    ];
    expect(leaks, isEmpty, reason: 'Timeline pixels show through the header');
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
