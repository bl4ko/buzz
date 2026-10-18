import 'package:buzz/features/channels/channel_tabs/channel_tab_editor_sheet.dart';
import 'package:buzz/features/channels/channel_tabs/channel_tabs_model.dart';
import 'package:buzz/features/channels/channel_tabs/channel_tabs_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Tabs extends ChannelTabsNotifier {
  _Tabs() : super('c');
  final saved = <List<ChannelTab>>[];

  @override
  ChannelTabsState build() => const ChannelTabsState('c');

  @override
  Future<void> save(List<ChannelTab> tabs) async => saved.add(tabs);
}

void main() {
  test('link tabs need https and a title', () {
    expect(
      submitTabForm(
        type: 'link',
        title: 'G',
        value: 'http://g.example',
        initial: null,
      ).$2,
      isNotNull,
    );
    expect(
      submitTabForm(
        type: 'link',
        title: ' ',
        value: 'https://g.example',
        initial: null,
      ).$2,
      isNotNull,
    );
    final (tab, error) = submitTabForm(
      type: 'link',
      title: 'G',
      value: 'https://g.example',
      initial: null,
    );
    expect(error, isNull);
    expect((tab!.type, tab.value), ('link', 'https://g.example'));
  });

  test('canvas tabs get a generated id and rename keeps id and value', () {
    final (canvas, _) = submitTabForm(
      type: 'canvas',
      title: 'Runbook',
      value: '',
      initial: null,
    );
    expect(RegExp(r'^[a-f0-9]{16}$').hasMatch(canvas!.value), isTrue);
    const old = ChannelTab(
      id: 't1',
      type: 'link',
      title: 'Old',
      value: 'https://a.example',
    );
    final (renamed, _) = submitTabForm(
      type: 'link',
      title: 'New',
      value: 'ignored',
      initial: old,
    );
    expect(
      (renamed!.id, renamed.title, renamed.value),
      ('t1', 'New', 'https://a.example'),
    );
  });

  testWidgets('adding a tab returns its id so the row can select it', (
    tester,
  ) async {
    final tabs = _Tabs();
    final results = <String?>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [channelTabsProvider('c').overrideWith(() => tabs)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () async => results.add(
                await showChannelTabEditor(
                  context,
                  ref,
                  channelId: 'c',
                  initial: null,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Runbooks');
    await tester.enterText(
      find.widgetWithText(TextField, 'Value'),
      'https://r.example',
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(tabs.saved.single.single.title, 'Runbooks');
    expect(results, [tabs.saved.single.single.id]);
  });
}
