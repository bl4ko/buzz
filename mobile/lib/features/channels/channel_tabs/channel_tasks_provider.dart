import 'dart:math';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/relay/relay.dart';
import '../channel_management_provider.dart';
import 'subscribe_while_alive.dart';
import 'thread_status.dart';

class ChannelTasksState {
  const ChannelTasksState([this.byRoot = const {}]);
  final Map<String, ThreadTask> byRoot;
  List<ThreadTask> get tasks => byRoot.values.toList();
  ThreadTaskGroups get groups => groupThreadTasks(byRoot.values);
  int get awaitingCount => groups.needsYou.length;
}

class ChannelTasksNotifier extends Notifier<ChannelTasksState> {
  ChannelTasksNotifier(this.channelId);

  final String channelId;
  (String, String?)? _scope;
  ChannelTasksState _tasks = const ChannelTasksState();

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
    _tasks = ChannelTasksState({..._tasks.byRoot, task.rootId: task});
    state = _tasks;
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
