import 'dart:math';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/relay/relay.dart';
import '../channel_management_provider.dart';
import 'subscribe_while_alive.dart';
import 'canvas_doc.dart';

class CanvasDocNotifier extends Notifier<CanvasVersion?> {
  CanvasDocNotifier(this.key);

  final (String, String) key;
  final List<NostrEvent> _events = [];

  @override
  CanvasVersion? build() {
    final connected = ref.watch(
      relaySessionProvider.select((s) => s.status == SessionStatus.connected),
    );
    final (channelId, canvasId) = key;
    if (connected) {
      subscribeWhileAlive(
        ref,
        NostrFilter(
          kinds: const [EventKind.channelCanvasDoc],
          tags: {
            '#h': [channelId],
            '#d': [canvasDTag(channelId, canvasId)],
          },
          limit: 50,
        ),
        receive,
      );
    }
    return latestCanvas(_events, channelId: channelId, canvasId: canvasId);
  }

  void receive(NostrEvent event) {
    if (_events.any((e) => e.id == event.id)) return;
    _events.add(event);
    final (channelId, canvasId) = key;
    state = latestCanvas(_events, channelId: channelId, canvasId: canvasId);
  }

  Future<CanvasSaveResult> save(
    String content,
    String? baseEventId, {
    bool force = false,
  }) async {
    if (canvasBytes(content) > canvasMaxBytes) {
      throw ArgumentError('Canvas is larger than 64 KB.');
    }
    if (!force && canvasConflict(baseEventId, state) != null) {
      return CanvasSaveResult.conflict;
    }
    final (channelId, canvasId) = key;
    NostrEvent? signed;
    await ref
        .read(channelActionsProvider)
        .saveCanvasDoc(
          channelId: channelId,
          canvasId: canvasId,
          content: content,
          createdAt: max(
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
            (state?.createdAt ?? 0) + 1,
          ),
          onSigned: (event) => signed = event,
        );
    final event = signed;
    if (event != null && ref.mounted) receive(event);
    return CanvasSaveResult.saved;
  }
}

final canvasDocProvider = NotifierProvider.autoDispose
    .family<CanvasDocNotifier, CanvasVersion?, (String, String)>(
      CanvasDocNotifier.new,
    );
