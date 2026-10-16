import 'package:buzz/features/channels/channel_tabs/thread_status.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter_test/flutter_test.dart';

const ch = '11111111-1111-4111-8111-111111111111';
final root = 'a' * 64;
final ask = 'b' * 64;

NostrEvent status(
  String id,
  String value,
  int createdAt, {
  String? rootId,
  String title = 'Rotate keys',
  String? askText,
  String channel = ch,
}) {
  final r = rootId ?? root;
  return NostrEvent(
    id: id,
    pubkey: 'c' * 64,
    createdAt: createdAt,
    kind: EventKind.threadStatus,
    tags: [
      ['d', r],
      ['h', channel],
      ['e', r],
      ['status', value],
      ['title', title],
      if (askText != null) ['ask', askText, ask],
    ],
    content: '',
    sig: '',
  );
}

void main() {
  test('parses the shared shape and rejects others', () {
    expect(
      ThreadTask.fromEvent(status('1', 'open', 1))!.status,
      TaskStatus.open,
    );
    expect(
      ThreadTask.fromEvent(
        status('2', 'awaiting_owner', 1, askText: 'Merge?'),
      )!.ask!.eventId,
      ask,
    );
    expect(ThreadTask.fromEvent(status('3', 'awaiting_owner', 1)), isNull);
    expect(
      ThreadTask.fromEvent(status('4', 'blocked', 1, askText: 'Q?')),
      isNull,
    );
    expect(ThreadTask.fromEvent(status('5', 'finished', 1)), isNull);
    expect(
      ThreadTask.fromEvent(status('6', 'open', 1, title: 'é' * 81)),
      isNull,
    );
    expect(
      ThreadTask.fromEvent(status('7', 'open', 1, title: 'é' * 80)),
      isNotNull,
    );
  });

  test('newest wins and ties keep the lower event id', () {
    final tasks = reduceThreadTasks([
      status('f2', 'done', 10),
      status('a1', 'blocked', 10),
      status('00', 'open', 5),
    ], channelId: ch);
    expect(tasks[root]!.eventId, 'a1');
    expect(
      reduceThreadTasks([
        status('1', 'open', 1, channel: 'other'),
      ], channelId: ch),
      isEmpty,
    );
  });

  test('groups put open with in progress and keep 20 done', () {
    final events = [
      status('o', 'open', 1, rootId: '1' * 64),
      status('w', 'awaiting_owner', 2, rootId: '2' * 64, askText: 'Q?'),
      status('b', 'blocked', 3, rootId: '3' * 64),
      for (var i = 0; i < 25; i++)
        status(
          'd$i',
          'done',
          100 + i,
          rootId: i.toRadixString(16).padLeft(64, '9'),
        ),
    ];
    final groups = groupThreadTasks(
      reduceThreadTasks(events, channelId: ch).values,
    );
    expect(
      [
        groups.needsYou.length,
        groups.inProgress.length,
        groups.blocked.length,
        groups.done.length,
      ],
      [1, 1, 1, 20],
    );
    expect(groups.done.first.eventId, 'd24');
  });

  test('tags and approval helpers', () {
    expect(
      threadStatusTags(
        rootId: root,
        channelId: ch,
        status: TaskStatus.done,
        title: 'T',
      ),
      [
        ['d', root],
        ['h', ch],
        ['e', root],
        ['status', 'done'],
        ['title', 'T'],
      ],
    );
    expect(
      isApprovalRequest([
        ['notification', 'approval'],
      ]),
      isTrue,
    );
    expect(
      isApprovalRequest([
        ['h', ch],
      ]),
      isFalse,
    );
  });
}
