import '../../../shared/relay/relay.dart';

enum TaskStatus { open, inProgress, awaitingOwner, blocked, done }

const _wire = {
  TaskStatus.open: 'open',
  TaskStatus.inProgress: 'in_progress',
  TaskStatus.awaitingOwner: 'awaiting_owner',
  TaskStatus.blocked: 'blocked',
  TaskStatus.done: 'done',
};

extension TaskStatusWire on TaskStatus {
  String get wire => _wire[this]!;
}

TaskStatus? taskStatusFromWire(String value) {
  for (final entry in _wire.entries) {
    if (entry.value == value) return entry.key;
  }
  return null;
}

const approveEmoji = '✅';
const denyEmoji = '❌';
final _hex64 = RegExp(r'^[0-9a-f]{64}$');

class ThreadTaskAsk {
  const ThreadTaskAsk({required this.text, required this.eventId});
  final String text;
  final String eventId;
}

class ThreadTask {
  const ThreadTask({
    required this.rootId,
    required this.channelId,
    required this.status,
    required this.title,
    required this.ask,
    required this.author,
    required this.createdAt,
    required this.eventId,
  });

  final String rootId;
  final String channelId;
  final TaskStatus status;
  final String title;
  final ThreadTaskAsk? ask;
  final String author;
  final int createdAt;
  final String eventId;

  static ThreadTask? fromEvent(NostrEvent event) {
    if (event.kind != EventKind.threadStatus || event.content.isNotEmpty) {
      return null;
    }
    List<String>? single(String name) {
      final rows = event.tags
          .where((t) => t.isNotEmpty && t.first == name)
          .toList();
      return rows.length == 1 ? rows.single : null;
    }

    final d = single('d');
    final h = single('h');
    final e = single('e');
    final statusRow = single('status');
    final titleRow = single('title');
    if (d == null ||
        h == null ||
        e == null ||
        statusRow == null ||
        titleRow == null) {
      return null;
    }
    if ([d, h, e, statusRow, titleRow].any((row) => row.length < 2)) {
      return null;
    }
    final rootId = d[1];
    if (!_hex64.hasMatch(rootId) ||
        e[1] != rootId ||
        (e.length > 3 && e[3].isNotEmpty)) {
      return null;
    }
    final status = taskStatusFromWire(statusRow[1]);
    final title = titleRow[1];
    if (status == null || title.trim().isEmpty || title.runes.length > 80) {
      return null;
    }
    final askRows = event.tags
        .where((t) => t.isNotEmpty && t.first == 'ask')
        .toList();
    if (askRows.length > 1) return null;
    ThreadTaskAsk? ask;
    if (askRows.isNotEmpty) {
      final row = askRows.single;
      if (row.length < 3 || row[1].trim().isEmpty || !_hex64.hasMatch(row[2])) {
        return null;
      }
      ask = ThreadTaskAsk(text: row[1], eventId: row[2]);
    }
    if ((status == TaskStatus.awaitingOwner) != (ask != null)) return null;
    return ThreadTask(
      rootId: rootId,
      channelId: h[1],
      status: status,
      title: title,
      ask: ask,
      author: event.pubkey,
      createdAt: event.createdAt,
      eventId: event.id,
    );
  }

  bool isNewerThan(ThreadTask other) => createdAt != other.createdAt
      ? createdAt > other.createdAt
      : eventId.compareTo(other.eventId) < 0;
}

Map<String, ThreadTask> reduceThreadTasks(
  Iterable<NostrEvent> events, {
  required String channelId,
}) {
  final tasks = <String, ThreadTask>{};
  for (final event in events) {
    final task = ThreadTask.fromEvent(event);
    if (task == null || task.channelId != channelId) continue;
    final current = tasks[task.rootId];
    if (current == null || task.isNewerThan(current)) tasks[task.rootId] = task;
  }
  return tasks;
}

class ThreadTaskGroups {
  const ThreadTaskGroups({
    required this.needsYou,
    required this.inProgress,
    required this.blocked,
    required this.done,
  });
  final List<ThreadTask> needsYou;
  final List<ThreadTask> inProgress;
  final List<ThreadTask> blocked;
  final List<ThreadTask> done;
}

ThreadTaskGroups groupThreadTasks(Iterable<ThreadTask> tasks) {
  int newestFirst(ThreadTask a, ThreadTask b) => b.createdAt != a.createdAt
      ? b.createdAt.compareTo(a.createdAt)
      : a.eventId.compareTo(b.eventId);
  List<ThreadTask> pick(bool Function(ThreadTask) test) =>
      tasks.where(test).toList()..sort(newestFirst);
  return ThreadTaskGroups(
    needsYou: pick((t) => t.status == TaskStatus.awaitingOwner),
    inProgress: pick(
      (t) => t.status == TaskStatus.open || t.status == TaskStatus.inProgress,
    ),
    blocked: pick((t) => t.status == TaskStatus.blocked),
    done: pick((t) => t.status == TaskStatus.done).take(20).toList(),
  );
}

List<List<String>> threadStatusTags({
  required String rootId,
  required String channelId,
  required TaskStatus status,
  required String title,
  ThreadTaskAsk? ask,
}) => [
  ['d', rootId],
  ['h', channelId],
  ['e', rootId],
  ['status', status.wire],
  ['title', String.fromCharCodes(title.runes.take(80))],
  if (status == TaskStatus.awaitingOwner && ask != null)
    ['ask', ask.text, ask.eventId],
];

bool isApprovalRequest(List<List<String>> tags) => tags.any(
  (tag) => tag.length > 1 && tag[0] == 'notification' && tag[1] == 'approval',
);
