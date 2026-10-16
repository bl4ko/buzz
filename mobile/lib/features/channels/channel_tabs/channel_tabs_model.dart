import 'dart:convert';
import 'dart:math';

import '../../../shared/relay/relay.dart';

const knownTabTypes = ['link', 'search', 'thread', 'canvas'];
final _slug = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final _hex64 = RegExp(r'^[0-9a-f]{64}$');
final _random = Random.secure();

class ChannelTab {
  const ChannelTab({
    required this.id,
    required this.type,
    required this.title,
    required this.value,
  });
  final String id;
  final String type;
  final String title;
  final String value;

  Map<String, String> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    'value': value,
  };
  ChannelTab copyWith({String? title}) =>
      ChannelTab(id: id, type: type, title: title ?? this.title, value: value);
}

List<ChannelTab>? parseChannelTabs(String content) {
  Object? decoded;
  try {
    decoded = jsonDecode(content);
  } on FormatException {
    return null;
  }
  if (decoded is! List || decoded.length > 50) return null;
  final tabs = <ChannelTab>[];
  final ids = <String>{};
  for (final item in decoded) {
    if (item is! Map) return null;
    final id = item['id'],
        type = item['type'],
        title = item['title'],
        value = item['value'];
    if (id is! String ||
        type is! String ||
        title is! String ||
        value is! String) {
      return null;
    }
    if (!_slug.hasMatch(id) ||
        !ids.add(id) ||
        type.isEmpty ||
        type.length > 32) {
      return null;
    }
    if (title.trim().isEmpty ||
        title.runes.length > 40 ||
        utf8.encode(value).length > 2048) {
      return null;
    }
    tabs.add(ChannelTab(id: id, type: type, title: title, value: value));
  }
  return tabs;
}

class LatestChannelTabs {
  const LatestChannelTabs({
    this.tabs = const [],
    this.createdAt = 0,
    this.eventId,
  });
  final List<ChannelTab> tabs;
  final int createdAt;
  final String? eventId;
  List<ChannelTab> get visible =>
      tabs.where((tab) => knownTabTypes.contains(tab.type)).toList();
}

LatestChannelTabs latestChannelTabs(
  Iterable<NostrEvent> events, {
  required String channelId,
}) {
  var best = const LatestChannelTabs();
  for (final event in events) {
    if (event.kind != EventKind.channelTabs) continue;
    String? first(String name) => event.tags
        .where((t) => t.length > 1 && t[0] == name)
        .map((t) => t[1])
        .firstOrNull;
    if (first('d') != channelId || first('h') != channelId) continue;
    final tabs = parseChannelTabs(event.content);
    if (tabs == null) continue;
    final newer =
        best.eventId == null ||
        event.createdAt > best.createdAt ||
        (event.createdAt == best.createdAt &&
            event.id.compareTo(best.eventId!) < 0);
    if (newer) {
      best = LatestChannelTabs(
        tabs: tabs,
        createdAt: event.createdAt,
        eventId: event.id,
      );
    }
  }
  return best;
}

String? validateTabValue(String type, String value) {
  final trimmed = value.trim();
  switch (type) {
    case 'link':
      final uri = Uri.tryParse(trimmed);
      return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
          ? null
          : 'Use an https link.';
    case 'search':
      return trimmed.isNotEmpty && trimmed.length <= 200
          ? null
          : 'Enter a search of 1 to 200 characters.';
    case 'thread':
      return _hex64.hasMatch(trimmed) ? null : 'Enter a thread root event ID.';
    default:
      return _slug.hasMatch(trimmed) ? null : 'Use letters, digits, - or _.';
  }
}

String newTabId() => List.generate(
  8,
  (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

List<ChannelTab> addTab(List<ChannelTab> tabs, ChannelTab tab) => [
  ...tabs,
  tab,
];

List<ChannelTab> renameTab(List<ChannelTab> tabs, String id, String title) => [
  for (final tab in tabs) tab.id == id ? tab.copyWith(title: title) : tab,
];

List<ChannelTab> removeTab(List<ChannelTab> tabs, String id) =>
    tabs.where((tab) => tab.id != id).toList();

List<ChannelTab> moveTab(List<ChannelTab> tabs, String id, int delta) {
  final index = tabs.indexWhere((tab) => tab.id == id);
  final target = index + delta;
  if (index < 0 || target < 0 || target >= tabs.length) return [...tabs];
  final next = [...tabs];
  final moved = next.removeAt(index);
  next.insert(target, moved);
  return next;
}

String encodeChannelTabs(List<ChannelTab> tabs) =>
    jsonEncode([for (final tab in tabs) tab.toJson()]);
