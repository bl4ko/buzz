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
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(Grid.twelve),
          sliver: SliverToBoxAdapter(
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
                if (grid.isNotEmpty)
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
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Grid.twelve),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: Grid.half,
              crossAxisSpacing: Grid.half,
            ),
            itemCount: grid.length,
            itemBuilder: (context, index) {
              final item = grid[index];
              final Widget tile = item.isVideo && item.thumb == null
                  ? ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      child: const Center(
                        child: Icon(Icons.play_circle_outline),
                      ),
                    )
                  : image(item.thumb ?? item.url);
              return KeyedSubtree(
                key: ValueKey('${item.messageId}:${item.url}'),
                child: InkWell(
                  key: const Key('files-media-item'),
                  onTap: () => widget.onOpenMessage(item),
                  child: tile,
                ),
              );
            },
          ),
        ),
        SliverList.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final item = rows[index];
            return ListTile(
              key: ValueKey('${item.messageId}:${item.url}'),
              title: Text(
                item.kind == FileLinkKind.link ? item.host : item.name,
              ),
              subtitle: Text(
                item.kind == FileLinkKind.link ? item.path : item.host,
              ),
              onTap: () => widget.onOpenMessage(item),
            );
          },
        ),
        if (shown.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(Grid.sm),
              child: Text('No files or links found.'),
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: Grid.twelve + MediaQuery.paddingOf(context).bottom,
          ),
        ),
      ],
    );
  }
}
