import 'dart:convert';

import 'package:buzz/features/channels/channel_tabs/channel_tabs_model.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter_test/flutter_test.dart';

const ch = '11111111-1111-4111-8111-111111111111';

NostrEvent tabsEvent(
  String id,
  int createdAt,
  List<Map<String, String>> tabs,
) => NostrEvent(
  id: id,
  pubkey: 'a' * 64,
  createdAt: createdAt,
  kind: EventKind.channelTabs,
  tags: [
    ['d', ch],
    ['h', ch],
  ],
  content: jsonEncode(tabs),
  sig: '',
);

void main() {
  test('parses lists and rejects invalid ones', () {
    expect(
      parseChannelTabs(
        jsonEncode([
          {
            'id': 't1',
            'type': 'link',
            'title': 'G',
            'value': 'https://g.example',
          },
        ]),
      )!.single.id,
      't1',
    );
    expect(parseChannelTabs('{}'), isNull);
    expect(
      parseChannelTabs(
        jsonEncode([
          {'id': 'bad id', 'type': 'link', 'title': 'A', 'value': ''},
        ]),
      ),
      isNull,
    );
    expect(
      parseChannelTabs(
        jsonEncode([
          {'id': 'a', 'type': 'link', 'title': 'A', 'value': ''},
          {'id': 'a', 'type': 'link', 'title': 'B', 'value': ''},
        ]),
      ),
      isNull,
    );
  });

  test('latest list wins and unknown types stay hidden but preserved', () {
    final latest = latestChannelTabs([
      tabsEvent('1', 10, [
        {
          'id': 'a',
          'type': 'link',
          'title': 'Old',
          'value': 'https://o.example',
        },
      ]),
      tabsEvent('2', 20, [
        {'id': 'b', 'type': 'search', 'title': 'CVE', 'value': 'CVE'},
        {'id': 'z', 'type': 'future', 'title': 'Z', 'value': ''},
      ]),
    ], channelId: ch);
    expect(latest.tabs.map((t) => t.id), ['b', 'z']);
    expect(latest.visible.map((t) => t.id), ['b']);
    expect(latest.createdAt, 20);
  });

  test('values and edits', () {
    expect(validateTabValue('link', 'https://g.example'), isNull);
    expect(validateTabValue('link', 'http://g.example'), isNotNull);
    expect(validateTabValue('search', ' '), isNotNull);
    expect(validateTabValue('thread', 'a' * 64), isNull);
    expect(validateTabValue('canvas', 'notes_1'), isNull);
    const a = ChannelTab(id: 'a', type: 'link', title: 'A', value: '');
    const b = ChannelTab(id: 'b', type: 'link', title: 'B', value: '');
    expect(moveTab([a, b], 'b', -1).map((t) => t.id), ['b', 'a']);
    expect(renameTab([a, b], 'a', 'Z').first.title, 'Z');
    expect(removeTab([a, b], 'a').map((t) => t.id), ['b']);
    expect(addTab([a], b).length, 2);
    expect(
      encodeChannelTabs([a]),
      jsonEncode([
        {'id': 'a', 'type': 'link', 'title': 'A', 'value': ''},
      ]),
    );
    expect(RegExp(r'^[a-f0-9]{16}$').hasMatch(newTabId()), isTrue);
  });
}
