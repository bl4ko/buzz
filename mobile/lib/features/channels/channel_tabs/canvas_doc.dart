import 'dart:convert';

import '../../../shared/relay/relay.dart';

const canvasMaxBytes = 65536;

enum CanvasSaveResult { saved, conflict }

class CanvasVersion {
  const CanvasVersion({
    required this.eventId,
    required this.author,
    required this.createdAt,
    required this.content,
  });
  final String eventId;
  final String author;
  final int createdAt;
  final String content;
}

String canvasDTag(String channelId, String canvasId) => '$channelId:$canvasId';

int canvasBytes(String content) => utf8.encode(content).length;

CanvasVersion? latestCanvas(
  Iterable<NostrEvent> events, {
  required String channelId,
  required String canvasId,
}) {
  NostrEvent? best;
  final d = canvasDTag(channelId, canvasId);
  for (final event in events) {
    if (event.kind != EventKind.channelCanvasDoc) continue;
    String? first(String name) => event.tags
        .where((t) => t.length > 1 && t[0] == name)
        .map((t) => t[1])
        .firstOrNull;
    if (first('d') != d || first('h') != channelId) continue;
    if (best == null ||
        event.createdAt > best.createdAt ||
        (event.createdAt == best.createdAt &&
            event.id.compareTo(best.id) < 0)) {
      best = event;
    }
  }
  final found = best;
  return found == null
      ? null
      : CanvasVersion(
          eventId: found.id,
          author: found.pubkey,
          createdAt: found.createdAt,
          content: found.content,
        );
}

CanvasVersion? canvasConflict(String? baseEventId, CanvasVersion? latest) =>
    latest != null && latest.eventId != baseEventId ? latest : null;
