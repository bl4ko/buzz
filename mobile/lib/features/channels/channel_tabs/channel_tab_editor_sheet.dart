import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/theme/theme.dart';
import 'channel_tabs_model.dart';
import 'channel_tabs_provider.dart';

(ChannelTab?, String?) submitTabForm({
  required String type,
  required String title,
  required String value,
  required ChannelTab? initial,
}) {
  final cleanTitle = title.trim();
  if (cleanTitle.isEmpty || cleanTitle.runes.length > 40) {
    return (null, 'Enter a title of 1 to 40 characters.');
  }
  if (initial != null) return (initial.copyWith(title: cleanTitle), null);
  final cleanValue = type == 'canvas' ? newTabId() : value.trim();
  final error = validateTabValue(type, cleanValue);
  if (error != null) return (null, error);
  return (
    ChannelTab(
      id: newTabId(),
      type: type,
      title: cleanTitle,
      value: cleanValue,
    ),
    null,
  );
}

Future<void> showChannelTabEditor(
  BuildContext context,
  WidgetRef ref, {
  required String channelId,
  required ChannelTab? initial,
}) async {
  var type = initial?.type ?? 'link';
  final title = TextEditingController(text: initial?.title ?? '');
  final value = TextEditingController(text: initial?.value ?? '');
  String? error;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(
          Grid.xs,
          Grid.xs,
          Grid.xs,
          Grid.xs + MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (initial == null)
              Wrap(
                spacing: Grid.half,
                children: [
                  for (final option in knownTabTypes)
                    ChoiceChip(
                      label: Text(option),
                      selected: type == option,
                      onSelected: (_) => setSheetState(() => type = option),
                    ),
                ],
              ),
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            if (initial == null && type != 'canvas')
              TextField(
                controller: value,
                decoration: const InputDecoration(labelText: 'Value'),
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
              ),
            FilledButton(
              onPressed: () async {
                final (tab, problem) = submitTabForm(
                  type: type,
                  title: title.text,
                  value: value.text,
                  initial: initial,
                );
                if (tab == null) {
                  setSheetState(() => error = problem);
                  return;
                }
                final notifier = ref.read(
                  channelTabsProvider(channelId).notifier,
                );
                final current = ref
                    .read(channelTabsProvider(channelId))
                    .latest
                    .tabs;
                await notifier.save(
                  initial == null
                      ? addTab(current, tab)
                      : renameTab(current, tab.id, tab.title),
                );
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              },
              child: Text(initial == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showChannelTabActions(
  BuildContext context,
  WidgetRef ref, {
  required String channelId,
  required ChannelTab tab,
}) async {
  final notifier = ref.read(channelTabsProvider(channelId).notifier);
  List<ChannelTab> current() =>
      ref.read(channelTabsProvider(channelId)).latest.tabs;
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('Rename'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showChannelTabEditor(
                context,
                ref,
                channelId: channelId,
                initial: tab,
              );
            },
          ),
          ListTile(
            title: const Text('Move left'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              notifier.save(moveTab(current(), tab.id, -1));
            },
          ),
          ListTile(
            title: const Text('Move right'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              notifier.save(moveTab(current(), tab.id, 1));
            },
          ),
          ListTile(
            title: const Text('Delete'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              notifier.save(removeTab(current(), tab.id));
            },
          ),
        ],
      ),
    ),
  );
}
