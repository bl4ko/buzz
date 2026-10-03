import 'package:buzz/features/activity/activity_projection.dart';
import 'package:buzz/features/activity/inbox_item.dart';
import 'package:buzz/features/activity/inbox_read_state.dart';
import 'package:buzz/shared/relay/nostr_models.dart';
import 'package:flutter_test/flutter_test.dart';

NostrEvent _event(
  String id, {
  int kind = 40002,
  String author = 'other',
  String channel = 'channel',
  String content = 'message',
  List<List<String>> tags = const [],
}) => NostrEvent(
  id: id,
  pubkey: author,
  createdAt: 100,
  kind: kind,
  tags: [
    ['h', channel],
    ...tags,
  ],
  content: content,
  sig: '',
);

void main() {
  test(
    'keeps mentions in muted channels and suppresses ordinary muted traffic',
    () {
      final feed = buildActivityFeed(
        [
          _event('muted'),
          _event(
            'mention',
            tags: [
              ['p', 'ME'],
            ],
          ),
          _event('other-channel', channel: 'inaccessible'),
          _event('self', author: 'me'),
        ],
        myPubkey: 'me',
        channelIds: {'channel'},
        mutedChannelIds: {'channel'},
      );
      expect(feed.all.map((item) => item.id), ['mention']);
    },
  );

  test(
    'includes followed and participated replies but omits unrelated replies',
    () {
      final feed = buildActivityFeed(
        [
          _event(
            'my-reply',
            author: 'me',
            tags: [
              ['e', 'participated', '', 'root'],
              ['e', 'participated', '', 'reply'],
            ],
          ),
          for (final root in ['participated', 'followed', 'unrelated'])
            _event(
              root,
              tags: [
                ['e', root, '', 'root'],
                ['e', root, '', 'reply'],
              ],
            ),
        ],
        myPubkey: 'me',
        channelIds: {'channel'},
        interestedRootIds: {'followed'},
      );
      expect(feed.all.map((item) => item.id).toSet(), {
        'participated',
        'followed',
      });
    },
  );

  test('deleted messages and removed reactions stay out of Activity', () {
    final feed = buildActivityFeed(
      [
        _event('mine', author: 'me'),
        _event(
          'reaction',
          kind: 7,
          content: '👍',
          tags: [
            ['e', 'mine'],
          ],
        ),
        _event(
          'removed-reaction',
          kind: 7,
          content: '✅',
          tags: [
            ['e', 'mine'],
          ],
        ),
        _event('deleted'),
        _event(
          'delete-message',
          kind: 9005,
          tags: [
            ['e', 'deleted'],
          ],
        ),
        _event(
          'delete-reaction',
          kind: 5,
          tags: [
            ['e', 'removed-reaction'],
          ],
        ),
      ],
      myPubkey: 'me',
      channelIds: {'channel'},
    );
    expect(feed.all.map((item) => item.id), ['reaction']);
  });

  test(
    'reaction previews use the edited message and read markers do not clear channel traffic',
    () {
      final feed = buildActivityFeed(
        [
          _event(
            'mine',
            author: 'me',
            tags: [
              ['e', 'root', '', 'root'],
              ['e', 'root', '', 'reply'],
            ],
          ),
          _event(
            'edit',
            author: 'me',
            kind: 40003,
            content: 'Updated text',
            tags: [
              ['e', 'mine'],
            ],
          ),
          _event(
            'reaction',
            kind: 7,
            content: '👍',
            tags: [
              ['e', 'mine'],
            ],
          ),
        ],
        myPubkey: 'me',
        channelIds: {'channel'},
      );
      final item = buildInboxItems(feed.all).single;
      expect(item.item.displayContent, 'Updated text');
      expect(item.item.targetEventId, 'mine');
      expect(item.threadRootId, 'root');
      expect(matchesInboxFilter(item, InboxFilter.reaction), isTrue);
      expect(groupedChannelReadTimestamp(item), isNull);
      expect(
        resolveInboxItemReadAt(
          item,
          markerOf: (id) => id == 'msg:reaction' ? 100 : null,
        ),
        100,
      );
      expect(
        isInboxItemDone(
          item,
          markerOf: (id) => id == 'msg:reaction' ? 100 : null,
          localUnreadOverrides: {},
          localDoneSet: {},
        ),
        isTrue,
      );
    },
  );
}
