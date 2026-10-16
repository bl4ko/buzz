import 'package:buzz/features/channels/channel_tabs/channel_tab_editor_sheet.dart';
import 'package:buzz/features/channels/channel_tabs/channel_tabs_model.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
