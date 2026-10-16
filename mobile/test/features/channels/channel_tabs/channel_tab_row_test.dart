import 'package:buzz/features/channels/channel_tabs/channel_tab_items.dart';
import 'package:buzz/features/channels/channel_tabs/channel_tab_row.dart';
import 'package:buzz/features/channels/channel_tabs/channel_tabs_model.dart';
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
    List<String>? events,
  }) async {
    final log = events ?? <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChannelTabRow(
            items: items,
            selected: 'tasks',
            canEdit: canEdit,
            onSelect: (key) => log.add('select:$key'),
            onAdd: () => log.add('add'),
            onCustomLongPress: (tab) => log.add('menu:${tab.id}'),
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
}
