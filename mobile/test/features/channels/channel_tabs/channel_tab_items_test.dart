import 'package:buzz/features/channels/channel_tabs/channel_tab_items.dart';
import 'package:buzz/features/channels/channel_tabs/channel_tabs_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const grafana = ChannelTab(
    id: 'g',
    type: 'link',
    title: 'Grafana',
    value: 'https://g.example',
  );

  test('built-in tabs show only with content and messages always', () {
    expect(
      buildChannelTabItems(
        taskCount: 0,
        awaitingCount: 0,
        pinCount: 0,
        fileCount: 0,
        customTabs: const [],
      ).map((i) => i.key),
      ['messages'],
    );
    final items = buildChannelTabItems(
      taskCount: 3,
      awaitingCount: 2,
      pinCount: 1,
      fileCount: 4,
      customTabs: const [grafana],
    );
    expect(items.map((i) => i.key), [
      'messages',
      'tasks',
      'pins',
      'files',
      'custom:g',
    ]);
    expect(items.map((i) => i.label), [
      'Messages',
      'Tasks',
      'Pins',
      'Files and links',
      'Grafana',
    ]);
    expect(items[1].badge, 2);
    expect(resolveSelectedTab(items.take(1).toList(), 'tasks'), 'messages');
  });

  test('custom tab labels use the title, or the host of a URL title', () {
    ChannelTab link(String title) => ChannelTab(
      id: 'x',
      type: 'link',
      title: title,
      value: 'https://grafana.example/d/abc',
    );
    expect(channelTabLabel(link('  Grafana  ')), 'Grafana');
    expect(
      channelTabLabel(link('https://www.grafana.example/d/abc?x=1')),
      'grafana.example',
    );
    expect(channelTabLabel(link('http://ci.example')), 'ci.example');
    expect(channelTabLabel(link('https://')), 'https://');
    final items = buildChannelTabItems(
      taskCount: 0,
      awaitingCount: 0,
      pinCount: 0,
      fileCount: 0,
      customTabs: [link('https://ci.example/runs')],
    );
    expect(items.last.label, 'ci.example');
  });

  test('permissions follow roles', () {
    expect(
      taskPermissions(role: 'owner', isCommunityOwner: false).canSetStatus,
      isFalse,
    );
    expect(
      taskPermissions(role: 'admin', isCommunityOwner: false).canSetStatus,
      isFalse,
    );
    expect(
      taskPermissions(role: 'admin', isCommunityOwner: false).canEditTabs,
      isTrue,
    );
    expect(
      taskPermissions(role: 'guest', isCommunityOwner: false).canEditCanvas,
      isFalse,
    );
    expect(
      taskPermissions(role: null, isCommunityOwner: true).canSetStatus,
      isTrue,
    );
  });
}
