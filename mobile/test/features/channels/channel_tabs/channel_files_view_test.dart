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
}
