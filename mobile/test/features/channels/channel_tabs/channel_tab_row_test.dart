import 'package:buzz/features/channels/channel_tabs/channel_tab_items.dart';
import 'package:buzz/features/channels/channel_tabs/channel_tab_row.dart';
import 'package:buzz/features/channels/channel_tabs/channel_tabs_model.dart';
import 'package:buzz/shared/theme/buzz_icons.dart';
import 'package:buzz/shared/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const custom = ChannelTab(
    id: 'g',
    type: 'link',
    title: 'Grafana',
    value: 'https://g.example',
  );
  const items = [
    ChannelTabItem(key: 'messages', label: 'Messages'),
    ChannelTabItem(key: 'tasks', label: 'Tasks', badge: 2),
    ChannelTabItem(key: 'custom:g', label: 'Grafana', custom: custom),
  ];

  Future<List<String>> pump(
    WidgetTester tester, {
    required bool canEdit,
    List<ChannelTabItem> tabs = items,
    ThemeData? theme,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    final log = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => SizedBox(
              height: channelTabRowHeightOf(context),
              child: ChannelTabRow(
                items: tabs,
                selected: 'tasks',
                canEdit: canEdit,
                onSelect: (key) => log.add('select:$key'),
                onAdd: () => log.add('add'),
                onCustomLongPress: (tab) => log.add('menu:${tab.id}'),
              ),
            ),
          ),
        ),
      ),
    );
    return log;
  }

  testWidgets('shows tabs and badge and reports selection', (tester) async {
    final log = await pump(tester, canEdit: false);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.byKey(const Key('channel-tab-add')), findsNothing);
    await tester.tap(find.text('Grafana'));
    expect(log, ['select:custom:g']);
  });

  testWidgets('editors can add and open the custom tab menu', (tester) async {
    final log = await pump(tester, canEdit: true);
    await tester.tap(find.byKey(const Key('channel-tab-add')));
    await tester.longPress(find.text('Grafana'));
    expect(log, ['add', 'menu:g']);
  });

  testWidgets('the selected tab has a clear label and no chip checkmark', (
    tester,
  ) async {
    await pump(tester, canEdit: false);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byIcon(Icons.check), findsNothing);
    final context = tester.element(find.text('Tasks'));
    final scheme = Theme.of(context).colorScheme;
    expect(
      tester.widget<Text>(find.text('Tasks')).style?.color,
      scheme.primary,
    );
    expect(
      tester.widget<Text>(find.text('Messages')).style?.color,
      scheme.onSurfaceVariant,
    );
    expect(
      find.byKey(const Key('channel-tab-indicator-tasks')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('channel-tab-indicator-messages')),
      findsNothing,
    );
  });

  testWidgets('tabs show an icon for their kind', (tester) async {
    await pump(
      tester,
      canEdit: false,
      tabs: const [
        ChannelTabItem(key: 'messages', label: 'Messages'),
        ChannelTabItem(key: 'tasks', label: 'Tasks'),
        ChannelTabItem(key: 'pins', label: 'Pins'),
        ChannelTabItem(key: 'files', label: 'Files and links'),
        ChannelTabItem(key: 'custom:g', label: 'Grafana', custom: custom),
      ],
    );
    for (final icon in [
      BuzzIcons.messageSquare,
      BuzzIcons.circleCheck,
      BuzzIcons.pin,
      BuzzIcons.link,
      BuzzIcons.externalLink,
    ]) {
      expect(find.byIcon(icon), findsOneWidget);
    }
  });

  testWidgets('selection is exposed to accessibility', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, canEdit: false);
    final node = tester.getSemantics(
      find.byKey(const Key('channel-tab-tasks')),
    );
    expect(node, isSemantics(isSelected: true, isButton: true));
    expect(node.label, contains('Tasks'));
    expect(node.label, contains('2 need you'));
    semantics.dispose();
  });

  testWidgets('selecting a tab keeps its accessibility node', (tester) async {
    final semantics = tester.ensureSemantics();
    var selected = 'tasks';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ChannelTabRow(
              items: items,
              selected: selected,
              canEdit: false,
              onSelect: (key) => setState(() => selected = key),
              onAdd: () {},
              onCustomLongPress: (_) {},
            ),
          ),
        ),
      ),
    );
    int idOf(String key) =>
        tester.getSemantics(find.byKey(Key('channel-tab-$key'))).id;
    final grafana = idOf('custom:g');
    final messages = idOf('messages');
    await tester.tap(find.byKey(const Key('channel-tab-custom:g')));
    await tester.pumpAndSettle();
    expect(selected, 'custom:g');
    expect(idOf('custom:g'), grafana);
    await tester.tap(find.byKey(const Key('channel-tab-messages')));
    await tester.pumpAndSettle();
    expect(selected, 'messages');
    expect(idOf('messages'), messages);
    semantics.dispose();
  });

  testWidgets('long labels ellipsize and large text grows the row', (
    tester,
  ) async {
    const long = [
      ChannelTabItem(
        key: 'custom:g',
        label: 'A very long dashboard title for the cluster',
        custom: custom,
      ),
      ChannelTabItem(key: 'tasks', label: 'Tasks', badge: 2),
    ];
    await pump(tester, canEdit: false, tabs: long, theme: AppTheme.dark());
    final label = tester.widget<Text>(
      find.text('A very long dashboard title for the cluster'),
    );
    expect(label.maxLines, 1);
    expect(label.overflow, TextOverflow.ellipsis);
    final normal = tester.getSize(find.byType(ChannelTabRow)).height;
    await pump(
      tester,
      canEdit: false,
      tabs: long,
      theme: AppTheme.dark(),
      textScaler: const TextScaler.linear(2),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(ChannelTabRow)).height,
      greaterThan(normal),
    );
  });

  testWidgets('a selected or added tab at the end scrolls fully into view', (
    tester,
  ) async {
    const checklists = ChannelTab(
      id: 'c',
      type: 'search',
      title: 'Checklists',
      value: 'checklist',
    );
    const added = ChannelTab(
      id: 'n',
      type: 'link',
      title: 'Runbooks',
      value: 'https://r.example',
    );
    const tabs = [
      ChannelTabItem(key: 'messages', label: 'Messages'),
      ChannelTabItem(key: 'tasks', label: 'Tasks', badge: 3),
      ChannelTabItem(key: 'files', label: 'Files and links'),
      ChannelTabItem(key: 'custom:c', label: 'Checklists', custom: checklists),
    ];
    var selected = 'messages';
    var shown = tabs;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return ChannelTabRow(
                    items: shown,
                    selected: selected,
                    canEdit: true,
                    onSelect: (key) => setState(() => selected = key),
                    onAdd: () {},
                    onCustomLongPress: (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    final row = tester.getRect(find.byType(ChannelTabRow));
    void expectFullyVisible(String key) {
      final tab = tester.getRect(find.byKey(Key('channel-tab-$key')));
      expect(tab.left, greaterThanOrEqualTo(row.left - 0.01), reason: key);
      expect(tab.right, lessThanOrEqualTo(row.right + 0.01), reason: key);
    }

    final files = tester.getRect(find.byKey(const Key('channel-tab-files')));
    expect(files.left, lessThan(row.right - 4));
    expect(files.right, greaterThan(row.right));
    await tester.tapAt(Offset(row.right - 2, files.center.dy));
    await tester.pumpAndSettle();
    expect(selected, 'files');
    expectFullyVisible('files');

    update(() => selected = 'custom:c');
    await tester.pumpAndSettle();
    expectFullyVisible('custom:c');

    update(() => selected = 'messages');
    await tester.pumpAndSettle();
    expectFullyVisible('messages');

    update(() {
      shown = [
        ...tabs,
        const ChannelTabItem(key: 'custom:n', label: 'Runbooks', custom: added),
      ];
      selected = 'custom:n';
    });
    await tester.pumpAndSettle();
    expectFullyVisible('custom:n');
  });
}
