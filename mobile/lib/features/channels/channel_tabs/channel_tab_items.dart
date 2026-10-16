import 'dart:math';

import 'package:flutter/widgets.dart';

import 'channel_tabs_model.dart';

const channelTabLabelSize = 14.0;

double channelTabRowHeightOf(BuildContext context) => max(
  44,
  MediaQuery.textScalerOf(context).scale(channelTabLabelSize) * 1.4 + 24,
);

String channelTabLabel(ChannelTab tab) {
  final title = tab.title.trim();
  final uri = Uri.tryParse(title);
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty) {
    return title;
  }
  return uri.host.startsWith('www.') ? uri.host.substring(4) : uri.host;
}

class ChannelTabItem {
  const ChannelTabItem({
    required this.key,
    required this.label,
    this.badge,
    this.custom,
  });
  final String key;
  final String label;
  final int? badge;
  final ChannelTab? custom;
}

List<ChannelTabItem> buildChannelTabItems({
  required int taskCount,
  required int awaitingCount,
  required int pinCount,
  required int fileCount,
  required List<ChannelTab> customTabs,
}) => [
  const ChannelTabItem(key: 'messages', label: 'Messages'),
  if (taskCount > 0)
    ChannelTabItem(
      key: 'tasks',
      label: 'Tasks',
      badge: awaitingCount > 0 ? awaitingCount : null,
    ),
  if (pinCount > 0) const ChannelTabItem(key: 'pins', label: 'Pins'),
  if (fileCount > 0)
    const ChannelTabItem(key: 'files', label: 'Files and links'),
  for (final tab in customTabs)
    ChannelTabItem(
      key: 'custom:${tab.id}',
      label: channelTabLabel(tab),
      custom: tab,
    ),
];

String resolveSelectedTab(List<ChannelTabItem> items, String selected) =>
    items.any((item) => item.key == selected) ? selected : 'messages';

class TaskPermissions {
  const TaskPermissions({
    required this.canSetStatus,
    required this.canEditTabs,
    required this.canEditCanvas,
  });
  final bool canSetStatus;
  final bool canEditTabs;
  final bool canEditCanvas;
}

TaskPermissions taskPermissions({
  required String? role,
  required bool isCommunityOwner,
}) => TaskPermissions(
  canSetStatus: isCommunityOwner,
  canEditTabs: isCommunityOwner || role == 'owner' || role == 'admin',
  canEditCanvas: isCommunityOwner || (role != null && role != 'guest'),
);
