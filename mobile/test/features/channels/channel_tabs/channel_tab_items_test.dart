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
