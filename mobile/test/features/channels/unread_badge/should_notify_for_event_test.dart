import 'package:buzz/features/channels/unread_badge/should_notify_for_event.dart';
import 'package:buzz/shared/relay/nostr_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _me = 'me';
const _agent = 'agent';
const _human = 'human';
const _huddleRoot = 'huddle-root';
const _otherRoot = 'other-root';

NostrEvent _event({
  required String pubkey,
  String? rootId,
  bool mentionsMe = false,
  bool broadcast = false,
}) => NostrEvent(
  id: '$pubkey-$rootId-$mentionsMe-$broadcast',
  pubkey: pubkey,
  createdAt: 1000,
  kind: EventKind.streamMessage,
  tags: [
    const ['h', 'parent'],
    if (rootId != null) ['e', rootId, '', 'reply'],
    if (mentionsMe) const ['p', _me],
    if (broadcast) const ['broadcast', '1'],
  ],
  content: 'hello',
  sig: '',
);

void main() {
  test('an active huddle thread notifies only for mentions by people', () {
    final cases = <(NostrEvent, bool, bool)>[
      (_event(pubkey: _agent, rootId: _huddleRoot), false, true),
      (
        _event(pubkey: _agent, rootId: _huddleRoot, mentionsMe: true),
        false,
        true,
      ),
      (
        _event(pubkey: _agent, rootId: _huddleRoot, broadcast: true),
        false,
        true,
      ),
      (_event(pubkey: _human, rootId: _huddleRoot), false, true),
      (
        _event(pubkey: _human, rootId: _huddleRoot, mentionsMe: true),
        true,
        true,
      ),
      (
        _event(pubkey: _human, rootId: _huddleRoot, broadcast: true),
        false,
        true,
      ),
      (_event(pubkey: _agent, rootId: _otherRoot), true, true),
      (_event(pubkey: _human, rootId: _otherRoot), true, true),
      (_event(pubkey: _agent), true, true),
      (_event(pubkey: _agent, mentionsMe: true), true, true),
      (
        _event(pubkey: _me, rootId: _huddleRoot, mentionsMe: true),
        false,
        false,
      ),
    ];

    for (final (event, quiet, loud) in cases) {
      bool notify({required bool active}) => shouldNotifyForEvent(
        event,
        _me,
        participatedRootIds: const {_huddleRoot, _otherRoot},
        quietRootIds: active ? const {_huddleRoot} : const {},
        quietAuthorPubkeys: active ? const {_agent} : const {},
      );
      expect(notify(active: true), quiet, reason: 'active ${event.id}');
      expect(notify(active: false), loud, reason: 'inactive ${event.id}');
    }
  });
}
