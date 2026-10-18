import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../shared/theme/buzz_icons.dart';
import '../../../shared/theme/theme.dart';
import 'channel_tab_items.dart';
import 'channel_tabs_model.dart';

IconData channelTabIcon(ChannelTabItem item) =>
    switch (item.custom?.type ?? item.key) {
      'messages' => BuzzIcons.messageSquare,
      'tasks' => BuzzIcons.circleCheck,
      'pins' => BuzzIcons.pin,
      'files' => BuzzIcons.link,
      'link' => BuzzIcons.externalLink,
      'search' => BuzzIcons.search,
      'thread' => BuzzIcons.messagesSquare,
      'canvas' => BuzzIcons.fileText,
      _ => BuzzIcons.circleDot,
    };

class ChannelTabRow extends StatefulWidget {
  const ChannelTabRow({
    super.key,
    required this.items,
    required this.selected,
    required this.canEdit,
    required this.onSelect,
    required this.onAdd,
    required this.onCustomLongPress,
  });

  final List<ChannelTabItem> items;
  final String selected;
  final bool canEdit;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<ChannelTab> onCustomLongPress;

  @override
  State<ChannelTabRow> createState() => _ChannelTabRowState();
}

class _ChannelTabRowState extends State<ChannelTabRow> {
  final _scroll = ScrollController();
  final _tabKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _revealSelected();
  }

  @override
  void didUpdateWidget(ChannelTabRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected ||
        !listEquals(
          [for (final item in oldWidget.items) item.key],
          [for (final item in widget.items) item.key],
        )) {
      _revealSelected();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tab = _tabKeys[widget.selected]?.currentContext?.findRenderObject();
      if (!mounted || tab == null || !_scroll.hasClients) return;
      final viewport = RenderAbstractViewport.of(tab);
      final position = _scroll.position;
      final start = viewport.getOffsetToReveal(tab, 0).offset;
      final end = math.min(viewport.getOffsetToReveal(tab, 1).offset, start);
      final target = position.pixels
          .clamp(end, start)
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((target - position.pixels).abs() < 0.5) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: channelTabRowHeightOf(context),
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Grid.half),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in widget.items)
              _ChannelTab(
                key: _tabKeys.putIfAbsent(item.key, GlobalKey.new),
                item: item,
                selected: item.key == widget.selected,
                onTap: () => widget.onSelect(item.key),
                onLongPress: item.custom != null && widget.canEdit
                    ? () => widget.onCustomLongPress(item.custom!)
                    : null,
              ),
            if (widget.canEdit)
              IconButton(
                key: const Key('channel-tab-add'),
                tooltip: 'Add tab',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  BuzzIcons.plus,
                  size: 18,
                  color: context.colors.onSurfaceVariant,
                ),
                onPressed: widget.onAdd,
              ),
          ],
        ),
      ),
    );
  }
}

class _ChannelTab extends StatelessWidget {
  const _ChannelTab({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final ChannelTabItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = selected ? colors.primary : colors.onSurfaceVariant;
    final badge = item.badge;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: Key('channel-tab-${item.key}'),
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(Grid.xxs),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Grid.twelve),
              child: Center(
                widthFactor: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      channelTabIcon(item),
                      size: MediaQuery.textScalerOf(context).scale(16),
                      color: color,
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.labelLarge?.copyWith(
                          fontSize: channelTabLabelSize,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: color,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 6),
                      _CountBadge(count: badge),
                    ],
                  ],
                ),
              ),
            ),
            if (selected)
              Positioned(
                key: Key('channel-tab-indicator-${item.key}'),
                left: Grid.xxs,
                right: Grid.xxs,
                bottom: 0,
                height: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: colors.error,
        borderRadius: BorderRadius.circular(Grid.xxs),
      ),
      child: Text(
        '$count',
        semanticsLabel: '$count need you',
        textAlign: TextAlign.center,
        style: context.textTheme.labelSmall?.copyWith(
          color: colors.onError,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
