import 'package:buzz/features/channels/channel_tabs/canvas_doc.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:flutter_test/flutter_test.dart';

const ch = '11111111-1111-4111-8111-111111111111';

NostrEvent doc(
  String id,
  String pubkey,
  int createdAt,
  String content, {
  String canvas = 'notes',
}) => NostrEvent(
  id: id,
  pubkey: pubkey,
  createdAt: createdAt,
  kind: EventKind.channelCanvasDoc,
  tags: [
    ['d', '$ch:$canvas'],
    ['h', ch],
  ],
  content: content,
  sig: '',
);

void main() {
  test('latest canvas picks newest then lower id', () {
    expect(
      latestCanvas(
        [doc('2', 'a', 10, 'x'), doc('1', 'b', 10, 'y')],
        channelId: ch,
        canvasId: 'notes',
      )!.eventId,
      '1',
    );
    expect(
      latestCanvas(
        [doc('1', 'a', 10, 'x', canvas: 'other')],
        channelId: ch,
        canvasId: 'notes',
      ),
      isNull,
    );
  });

  test('conflict only when the base is not the latest', () {
    final latest = latestCanvas(
      [doc('2', 'b', 20, 'theirs')],
      channelId: ch,
      canvasId: 'notes',
    );
    expect(canvasConflict('1', latest)?.author, 'b');
    expect(canvasConflict('2', latest), isNull);
    expect(canvasDTag(ch, 'notes'), '$ch:notes');
  });
}
