import 'package:buzz/features/channels/channel_tabs/channel_files_view.dart';
import 'package:buzz/features/channels/channel_tabs/files_and_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FileLinkItem item(
  String id,
  FileLinkKind kind, {
  String name = 'x',
  int createdAt = 10,
}) => FileLinkItem(
  kind: kind,
  url: 'https://cdn.example/$id',
  name: name,
  host: 'cdn.example',
  path: '/$id',
  thumb: null,
  messageId: id,
  rootId: null,
  createdAt: createdAt,
);

void main() {
  final items = [
    for (var i = 0; i < 10; i++)
      item('p$i', FileLinkKind.media, createdAt: 100 - i),
    item('l1', FileLinkKind.link, name: 'grafana.xqx.uk/d/abc'),
    item('f1', FileLinkKind.file, name: 'report.pdf'),
  ];

  testWidgets('grid with See all, rows, filters, search, open', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChannelFilesView(
            items: items,
            onOpenMessage: (i) => opened.add(i.messageId),
            imageBuilder: (url) => const SizedBox(width: 10, height: 10),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('files-media-item')), findsNWidgets(8));
    await tester.tap(find.text('See all'));
    await tester.pump();
    expect(find.byKey(const Key('files-media-item')), findsNWidgets(10));
    await tester.tap(find.text('All'));
    await tester.enterText(find.byKey(const Key('files-search')), 'report');
    await tester.pump();
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.byKey(const Key('files-media-item')), findsNothing);
    await tester.tap(find.text('report.pdf'));
    expect(opened, ['f1']);
  });

  testWidgets('a video without a thumbnail shows a play tile, not an image', (
    tester,
  ) async {
    final requested = <String>[];
    final video = FileLinkItem(
      kind: FileLinkKind.media,
      url: 'https://cdn.example/v.mp4',
      name: 'v.mp4',
      host: 'cdn.example',
      path: '/v.mp4',
      thumb: null,
      messageId: 'v',
      rootId: null,
      createdAt: 1,
      isVideo: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChannelFilesView(
            items: [video],
            onOpenMessage: (_) {},
            imageBuilder: (url) {
              requested.add(url);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
    expect(requested, isEmpty);
  });

  testWidgets('a long list builds lazily', (tester) async {
    final many = [
      for (var i = 0; i < 200; i++)
        item('l$i', FileLinkKind.link, name: 'h/$i'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChannelFilesView(items: many, onOpenMessage: (_) {}),
        ),
      ),
    );
    expect(find.byType(ListTile).evaluate().length, lessThan(40));
  });

  testWidgets('the last row scrolls above the bottom safe area', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: ChannelFilesView(
            items: [
              for (var i = 0; i < 30; i++)
                item('f$i', FileLinkKind.file, name: 'file-$i.pdf'),
            ],
            onOpenMessage: (_) {},
          ),
        ),
      ),
    );
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -5000),
      5000,
    );
    await tester.pumpAndSettle();
    final lastRow = find.ancestor(
      of: find.text('file-29.pdf'),
      matching: find.byType(ListTile),
    );
    expect(tester.getBottomLeft(lastRow).dy, lessThanOrEqualTo(600 - 34));
  });
}
