import 'package:flutter/material.dart';

import '../../../shared/theme/theme.dart';
import '../../../shared/relay/media_image.dart';
import 'files_and_links.dart';

class ChannelFilesView extends StatefulWidget {
  const ChannelFilesView({
    super.key,
    required this.items,
    required this.onOpenMessage,
    this.imageBuilder,
  });

  final List<FileLinkItem> items;
  final ValueChanged<FileLinkItem> onOpenMessage;
  final Widget Function(String url)? imageBuilder;

  @override
  State<ChannelFilesView> createState() => _ChannelFilesViewState();
}

class _ChannelFilesViewState extends State<ChannelFilesView> {
  FileLinkFilter _filter = FileLinkFilter.all;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final shown = filterFilesAndLinks(widget.items, _filter, _query);
    final media = shown.where((i) => i.kind == FileLinkKind.media).toList();
    final rows = _filter == FileLinkFilter.media
        ? const <FileLinkItem>[]
        : shown.where((i) => i.kind != FileLinkKind.media).toList();
    final grid = _filter == FileLinkFilter.media
        ? media
        : media.take(8).toList();
    final image =
        widget.imageBuilder ?? (url) => MediaImage(url: url, fit: BoxFit.cover);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Grid.twelve),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('files-search'),
            decoration: const InputDecoration(
              hintText: 'Search files and links',
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          Wrap(
            spacing: Grid.half,
            children: [
              for (final (filter, label) in const [
                (FileLinkFilter.all, 'All'),
                (FileLinkFilter.files, 'Files'),
                (FileLinkFilter.media, 'Media'),
                (FileLinkFilter.links, 'Links'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
            ],
          ),
          if (grid.isNotEmpty) ...[
            Row(
              children: [
                const Expanded(child: Text('Photos and videos')),
                if (_filter != FileLinkFilter.media && media.length > 8)
                  TextButton(
                    onPressed: () =>
                        setState(() => _filter = FileLinkFilter.media),
                    child: const Text('See all'),
                  ),
              ],
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final cell = (constraints.maxWidth - 3 * Grid.half) / 4;
                return Wrap(
                  spacing: Grid.half,
                  runSpacing: Grid.half,
                  children: [
                    for (final item in grid)
                      SizedBox(
                        width: cell,
                        height: cell,
                        child: InkWell(
                          key: const Key('files-media-item'),
                          onTap: () => widget.onOpenMessage(item),
                          child: image(item.thumb ?? item.url),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
          for (final item in rows)
            ListTile(
              title: Text(
                item.kind == FileLinkKind.link ? item.host : item.name,
              ),
              subtitle: Text(
                item.kind == FileLinkKind.link ? item.path : item.host,
              ),
              onTap: () => widget.onOpenMessage(item),
            ),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.all(Grid.sm),
              child: Text('No files or links found.'),
            ),
        ],
      ),
    );
  }
}
