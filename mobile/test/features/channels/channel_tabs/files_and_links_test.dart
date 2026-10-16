import 'package:buzz/features/channels/channel_tabs/files_and_links.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter_test/flutter_test.dart';

NostrEvent message(
  String id,
  String content, {
  List<List<String>> tags = const [],
  int createdAt = 10,
}) => NostrEvent(
  id: id,
  pubkey: 'a' * 64,
  createdAt: createdAt,
  kind: EventKind.streamMessage,
  tags: [
    ['h', 'c'],
    ...tags,
  ],
  content: content,
  sig: '',
);

void main() {
  test('classifies media, files, and links newest first', () {
    final items = extractFilesAndLinks([
      message('m1', 'see https://grafana.xqx.uk/d/abc?x=1).', createdAt: 30),
      message(
        'm2',
        'https://cdn.example/p.png',
        tags: [
          ['imeta', 'url https://cdn.example/p.png', 'm image/png'],
        ],
        createdAt: 20,
      ),
      message(
        'm3',
        'report',
        tags: [
          [
            'imeta',
            'url https://cdn.example/r.pdf',
            'm application/pdf',
            'filename report.pdf',
          ],
        ],
      ),
    ]);
    expect(items.map((i) => (i.kind, i.messageId)), [
      (FileLinkKind.link, 'm1'),
      (FileLinkKind.media, 'm2'),
      (FileLinkKind.file, 'm3'),
    ]);
    expect(items.first.url, 'https://grafana.xqx.uk/d/abc?x=1');
    expect((items.first.host, items.first.path), ('grafana.xqx.uk', '/d/abc'));
    expect(items.last.name, 'report.pdf');
    expect(
      filterFilesAndLinks(
        items,
        FileLinkFilter.links,
        '',
      ).map((i) => i.messageId),
      ['m1'],
    );
    expect(
      filterFilesAndLinks(
        items,
        FileLinkFilter.all,
        'REPORT',
      ).map((i) => i.messageId),
      ['m3'],
    );
  });
}
