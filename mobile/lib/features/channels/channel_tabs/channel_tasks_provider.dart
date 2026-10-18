import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/relay/relay.dart';
import '../channel_management_provider.dart';
import 'subscribe_while_alive.dart';
import 'thread_status.dart';

class ChannelTasksState {
  const ChannelTasksState([this.byRoot = const {}, this.decisions = const {}]);
  final Map<String, ThreadTask> byRoot;
  final Map<String, OwnerDecision> decisions;
  List<ThreadTask> get tasks => byRoot.values.toList();
  ThreadTaskGroups get groups => groupThreadTasks(byRoot.values, decisions);
  int get awaitingCount => groups.needsYou.length;
}

class ChannelTasksNotifier extends Notifier<ChannelTasksState> {
  ChannelTasksNotifier(this.channelId);

  final String channelId;
  (String, String?)? _scope;
  ChannelTasksState _tasks = const ChannelTasksState();
  final Map<String, NostrEvent> _reactions = {};
  final Map<String, OwnerDecision> _sent = {};
  final Map<String, Object> _askSubscriptions = {};
  final Map<String, void Function()> _askCancels = {};
  bool _connected = false;
  String? _me;

  @override
  ChannelTasksState build() {
    final config = ref.watch(relayConfigProvider);
    final connected = ref.watch(
      relaySessionProvider.select((s) => s.status == SessionStatus.connected),
    );
    final scope = (config.baseUrl, config.nsec);
    if (scope != _scope) {
      _scope = scope;
      _tasks = const ChannelTasksState();
      _reactions.clear();
      _sent.clear();
    }
    _connected = connected;
    _me = ref.watch(myPubkeyProvider)?.toLowerCase();
    ref.onDispose(() {
      for (final cancel in _askCancels.values) {
        cancel();
      }
      _askCancels.clear();
      _askSubscriptions.clear();
    });
    for (final task in _tasks.byRoot.values) {
      _watchAsk(task);
    }
    if (connected) {
      subscribeWhileAlive(
        ref,
        NostrFilter(
          kinds: const [EventKind.threadStatus],
          tags: {
            '#h': [channelId],
          },
          limit: 500,
        ),
        receive,
      );
    }
    return _tasks;
  }

  void receive(NostrEvent event) {
    final task = ThreadTask.fromEvent(event);
    if (task == null || task.channelId != channelId) return;
    final current = _tasks.byRoot[task.rootId];
    if (current != null && !task.isNewerThan(current)) return;
    _tasks = ChannelTasksState({
      ..._tasks.byRoot,
      task.rootId: task,
    }, _tasks.decisions);
    state = _tasks;
    _watchAsk(task);
  }

  void _watchAsk(ThreadTask task) {
    final askId = task.ask?.eventId;
    final me = _me;
    if (!_connected ||
        me == null ||
        askId == null ||
        _askSubscriptions.containsKey(askId)) {
      return;
    }
    final token = Object();
    _askSubscriptions[askId] = token;
    unawaited(
      ref
          .read(relaySessionProvider.notifier)
          .subscribe(
            NostrFilter(
              kinds: const [EventKind.reaction],
              authors: [me],
              tags: {
                '#e': [askId],
                '#h': [channelId],
              },
              limit: 50,
            ),
            _receiveReaction,
          )
          .then(
            (cancel) {
              if (identical(_askSubscriptions[askId], token)) {
                _askCancels[askId] = cancel;
              } else {
                cancel();
              }
            },
            onError: (Object _) {
              if (identical(_askSubscriptions[askId], token)) {
                _askSubscriptions.remove(askId);
              }
            },
          ),
    );
  }

  void _receiveReaction(NostrEvent event) {
    final me = _me;
    if (me == null || !ref.mounted || _reactions.containsKey(event.id)) {
      return;
    }
    _reactions[event.id] = event;
    _publishDecisions(me);
  }

  void _publishDecisions(String me) {
    final decisions = {..._sent, ...ownerDecisions(_reactions.values, me)};
    if (mapEquals(decisions, _tasks.decisions)) return;
    _tasks = ChannelTasksState(_tasks.byRoot, decisions);
    state = _tasks;
  }

  Future<void> decide(String askId, OwnerDecision decision) async {
    await ref
        .read(channelActionsProvider)
        .addReaction(
          askId,
          decision == OwnerDecision.approve ? approveEmoji : denyEmoji,
        );
    final me = _me;
    if (me == null || !ref.mounted) return;
    _sent.putIfAbsent(askId.toLowerCase(), () => decision);
    _publishDecisions(me);
  }

  Future<void> markDone(ThreadTask task) async {
    NostrEvent? signed;
    await ref
        .read(channelActionsProvider)
        .setThreadStatus(
          channelId: channelId,
          rootId: task.rootId,
          status: TaskStatus.done,
          title: task.title,
          createdAt: max(
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
            task.createdAt + 1,
          ),
          onSigned: (event) => signed = event,
        );
    final event = signed;
    if (event != null && ref.mounted) receive(event);
  }
}

final channelTasksProvider = NotifierProvider.autoDispose
    .family<ChannelTasksNotifier, ChannelTasksState, String>(
      ChannelTasksNotifier.new,
    );
