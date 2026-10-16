import 'package:flutter/material.dart';

import '../../../shared/theme/theme.dart';
import 'channel_tab_items.dart';
import 'channel_tabs_model.dart';

class ChannelTabRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return SizedBox(
      height: channelTabRowHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Grid.xs),
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Grid.half),
              child: GestureDetector(
                onLongPress: item.custom != null && canEdit
                    ? () => onCustomLongPress(item.custom!)
                    : null,
                child: ChoiceChip(
                  key: Key('channel-tab-${item.key}'),
                  selected: item.key == selected,
                  onSelected: (_) => onSelect(item.key),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(item.label),
                      if (item.badge != null) ...[
                        const SizedBox(width: Grid.xxs),
                        Badge(label: Text('${item.badge}')),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          if (canEdit)
            IconButton(
              key: const Key('channel-tab-add'),
              tooltip: 'Add tab',
              icon: const Icon(Icons.add),
              onPressed: onAdd,
            ),
        ],
      ),
    );
  }
}
