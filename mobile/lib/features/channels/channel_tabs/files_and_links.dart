import '../../../shared/relay/relay.dart';
import '../message_media.dart';

enum FileLinkKind { file, media, link }

enum FileLinkFilter { all, files, media, links }

class FileLinkItem {
  const FileLinkItem({
    required this.kind,
    required this.url,
    required this.name,
    required this.host,
    required this.path,
    required this.thumb,
    required this.messageId,
    required this.rootId,
    required this.createdAt,
    this.isVideo = false,
  });
  final FileLinkKind kind;
  final String url;
  final String name;
  final String host;
  final String path;
  final String? thumb;
  final String messageId;
  final String? rootId;
  final int createdAt;
  final bool isVideo;
}

final _url = RegExp(r'''https?://[^\s<>"'`]+''');
final _trailing = RegExp(r'[).,;:!?\]]+$');

String? _rootOf(List<List<String>> tags) {
  String? reply;
  for (final tag in tags) {
    if (tag.length < 4 || tag[0] != 'e') continue;
    if (tag[3] == 'root') return tag[1];
    if (tag[3] == 'reply') reply = tag[1];
  }
  return reply;
}

List<FileLinkItem> extractFilesAndLinks(Iterable<NostrEvent> events) {
  final items = <String, FileLinkItem>{};
  for (final event in events) {
    final rootId = _rootOf(event.tags);
    final imeta = parseImetaTags(event.tags);
    for (final entry in imeta.values) {
      final uri = Uri.tryParse(entry.url);
      if (uri == null || uri.host.isEmpty) continue;
      final media = RegExp(r'^(image|video)/').hasMatch(entry.mimeType ?? '');
      items['${event.id}:${entry.url}'] = FileLinkItem(
        kind: media ? FileLinkKind.media : FileLinkKind.file,
        url: entry.url,
        name:
            entry.filename ??
            (uri.pathSegments.isEmpty ? uri.host : uri.pathSegments.last),
        host: uri.host,
        path: uri.path,
        thumb: entry.thumb ?? entry.image,
        messageId: event.id,
        rootId: rootId,
        createdAt: event.createdAt,
        isVideo: (entry.mimeType ?? '').startsWith('video/'),
      );
    }
    for (final match in _url.allMatches(event.content)) {
      final url = match.group(0)!.replaceAll(_trailing, '');
      final uri = Uri.tryParse(url);
      final key = '${event.id}:$url';
      if (uri == null ||
          uri.host.isEmpty ||
          imeta.containsKey(url) ||
          items.containsKey(key)) {
        continue;
      }
      items[key] = FileLinkItem(
        kind: FileLinkKind.link,
        url: url,
        name: '${uri.host}${uri.path}',
        host: uri.host,
        path: uri.path,
        thumb: null,
        messageId: event.id,
        rootId: rootId,
        createdAt: event.createdAt,
      );
    }
  }
  return items.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

List<FileLinkItem> filterFilesAndLinks(
  List<FileLinkItem> items,
  FileLinkFilter filter,
  String query,
) {
  final needle = query.trim().toLowerCase();
  const kinds = {
    FileLinkFilter.files: FileLinkKind.file,
    FileLinkFilter.media: FileLinkKind.media,
    FileLinkFilter.links: FileLinkKind.link,
  };
  return items
      .where(
        (item) => filter == FileLinkFilter.all || item.kind == kinds[filter],
      )
      .where(
        (item) =>
            needle.isEmpty ||
            '${item.name} ${item.url}'.toLowerCase().contains(needle),
      )
      .toList();
}
