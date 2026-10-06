part of '../channel_detail_page_test.dart';

const _speechChannel = MethodChannel('buzz/huddle_speech');
const _huddleAgentKey =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

NostrEvent _threadReply({
  required String id,
  required String pubkey,
  required String content,
  required String rootId,
  required int createdAt,
  bool voiceFinal = false,
}) => _textMsg(
  id: id,
  pubkey: pubkey,
  content: content,
  createdAt: createdAt,
  extraTags: [
    ['e', rootId, '', 'reply'],
    if (voiceFinal) const ['voice', 'final'],
  ],
);

class _PublishedEvents extends RelaySessionNotifier {
  final events = <NostrEvent>[];

  @override
  SessionState build() => const SessionState(status: SessionStatus.connected);

  @override
  Future<NostrEvent> publish(
    NostrEvent event, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    events.add(event);
    return event;
  }
}

SendMessage _recordingSendMessage(
  _PublishedEvents relay, {
  List<ChannelMember> members = const [],
}) => SendMessage(
  signedEventRelay: SignedEventRelay(
    session: relay,
    nsec: nostr.Keys.generate().nsec,
  ),
  fetchMembers: (_) async => members,
  readUserCache: () => const {},
  addLocalMessage: (_, _) {},
  completeLocalMessage: (_, _) {},
  removeLocalMessage: (_, _) {},
);

void huddleThreadTests() {
  testWidgets('a huddle card shows its thread and opens a huddle head', (
    tester,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final replies = [
      _threadReply(
        id: 'thread-huddle-reply-1',
        pubkey: 'bob',
        content: 'Can you check the logs?',
        rootId: 'thread-huddle',
        createdAt: now + 1,
      ),
      _threadReply(
        id: 'thread-huddle-reply-2',
        pubkey: 'agent',
        content: 'Logs are clean.',
        rootId: 'thread-huddle',
        createdAt: now + 2,
      ),
    ];
    await tester.pumpWidget(
      _buildTestable(
        messages: [
          _huddleMsg(
            id: 'thread-huddle',
            kind: EventKind.huddleStarted,
            createdAt: now,
            chatInThread: true,
          ),
          ...replies,
        ],
        threadReplies: {'thread-huddle': replies},
        users: const {
          'alice': UserProfile(pubkey: 'alice', displayName: 'Alice'),
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Huddle in progress'), findsOneWidget);
    expect(find.text('Logs are clean.'), findsNothing);
    final summary = find.byKey(const ValueKey('thread-summary-thread-huddle'));
    expect(summary, findsOneWidget);
    expect(
      find.descendant(of: summary, matching: find.textContaining('2 replies')),
      findsOneWidget,
    );

    await tester.tap(summary);
    await tester.pumpAndSettle();

    expect(find.byType(ThreadDetailPage), findsOneWidget);
    expect(find.byKey(const ValueKey('thread-system-head')), findsOneWidget);
    expect(find.text('Started a huddle'), findsOneWidget);
    expect(
      find.textContaining('ephemeral_channel_id', findRichText: true),
      findsNothing,
    );
    expect(
      find.text('Can you check the logs?', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Logs are clean.', findRichText: true), findsOneWidget);
  });

  testWidgets('agent typing in the huddle thread shows its working state', (
    tester,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    TypingEntry typingIn(String threadHeadId) => TypingEntry(
      pubkey: 'agent',
      threadHeadId: threadHeadId,
      expiresAtMs: DateTime.now().millisecondsSinceEpoch + 8000,
    );
    final typing = _FakeTypingNotifier([typingIn('other-thread')]);
    await tester.pumpWidget(
      _buildTestable(
        messages: [
          _huddleMsg(
            id: 'typing-huddle',
            kind: EventKind.huddleStarted,
            pubkey: 'self',
            createdAt: now,
            chatInThread: true,
          ),
        ],
        users: const {
          'agent': UserProfile(pubkey: 'agent', displayName: 'Pollen'),
          'self': UserProfile(pubkey: 'self', displayName: 'Self'),
        },
        members: [
          ChannelMember(pubkey: 'agent', role: 'bot', joinedAt: DateTime(2025)),
        ],
        loadChannelBotPubkeys: () async => const {'agent'},
        typingNotifier: typing,
        relayConfigNotifier: _HuddleRelayConfigNotifier(),
        huddleCurrentPubkey: 'self',
        huddleMediaFactory: _HuddleTestMedia.new,
        huddleTransportFactory: (_) => _HuddleTestTransport(
          peers: const {
            1: HuddlePeer(pubkey: 'self', peerIndex: 1, epoch: 0),
            2: HuddlePeer(pubkey: 'agent', peerIndex: 2, epoch: 0),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 200));
    const preparing = ValueKey('huddle-agent-preparing-response-agent');
    expect(find.byKey(preparing), findsNothing);

    typing.setEntries([typingIn('typing-huddle')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(preparing), findsOneWidget);
  });

  for (final threaded in [true, false]) {
    testWidgets(
      threaded
          ? 'iPhone speech and chat use the huddle thread in the parent'
          : 'a huddle start without chat=thread keeps speech in its room',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = const Size(1170, 2532);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final nativeCalls = <String>[];
        messenger.setMockMethodCallHandler(_speechChannel, (call) async {
          nativeCalls.add(call.method);
          return call.method == 'microphoneMode' ? 'voiceIsolation' : null;
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(_speechChannel, null),
        );
        final spoken = <String>[];
        final client = http_testing.MockClient((request) async {
          if (request.url.path.endsWith('/transcribe')) {
            return http.Response('{"text":"Check the deploy"}', 200);
          }
          spoken.add(
            '${request.url.path} ${(jsonDecode(request.body) as Map)['text']}',
          );
          return http.Response.bytes(const [1, 2, 3], 200);
        });
        final relay = _PublishedEvents();
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final start = _huddleMsg(
          id: 'speech-huddle',
          kind: EventKind.huddleStarted,
          pubkey: 'self',
          createdAt: now,
          chatInThread: threaded,
        );
        final messages = _FakeMessagesNotifier([start]);
        final agent = ChannelMember(
          pubkey: _huddleAgentKey,
          role: 'bot',
          joinedAt: DateTime(2025),
        );

        await http.runWithClient(() async {
          await tester.pumpWidget(
            _buildTestable(
              messages: const [],
              messagesNotifier: messages,
              members: [agent],
              huddleMembers: [agent],
              userCacheNotifier: _FakeUserCacheNotifier(const {
                _huddleAgentKey: UserProfile(
                  pubkey: _huddleAgentKey,
                  displayName: 'Pollen',
                ),
                'self': UserProfile(pubkey: 'self', displayName: 'Self'),
              }),
              threadReplies: {'speech-huddle': const []},
              relayConfigNotifier: _HuddleRelayConfigNotifier(),
              huddleCurrentPubkey: 'self',
              huddleHumanCountLoader: (_) async => 2,
              huddleMediaFactory: _HuddleTestMedia.new,
              huddleTransportFactory: (_) => _HuddleTestTransport(
                peers: const {
                  1: HuddlePeer(pubkey: 'self', peerIndex: 1, epoch: 0),
                  2: HuddlePeer(
                    pubkey: _huddleAgentKey,
                    peerIndex: 2,
                    epoch: 0,
                  ),
                },
              ),
              sendMessage: _recordingSendMessage(relay, members: [agent]),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, 'Join'));
          await tester.pumpAndSettle();
          expect(nativeCalls, contains('start'));
          expect(find.text('Listening on this device'), findsOneWidget);

          unawaited(
            messenger.handlePlatformMessage(
              _speechChannel.name,
              const StandardMethodCodec().encodeMethodCall(
                MethodCall('audio', {
                  'audio': Uint8List.fromList([1, 2]),
                }),
              ),
              (_) {},
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pump();

          final transcript = relay.events.single;
          expect(transcript.content, 'Check the deploy');
          expect(transcript.kind, EventKind.streamMessage);
          expect(
            transcript.tags,
            contains(equals(const ['p', _huddleAgentKey])),
          );
          if (threaded) {
            expect(transcript.tags, contains(equals(const ['h', _channelId])));
            expect(
              transcript.tags,
              contains(equals(const ['e', 'speech-huddle', '', 'reply'])),
            );
          } else {
            expect(
              transcript.tags,
              contains(equals(const ['h', _huddleChannelId])),
            );
            expect(transcript.tags.where((tag) => tag.first == 'e'), isEmpty);
          }

          final later = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60;
          final parentEvents = [
            start,
            _textMsg(
              id: 'agent-top-level',
              pubkey: _huddleAgentKey,
              content: 'Unrelated channel report.',
              createdAt: later,
              extraTags: const [
                ['voice', 'final'],
              ],
            ),
            _threadReply(
              id: 'agent-progress',
              pubkey: _huddleAgentKey,
              content: 'Reading deploy logs',
              rootId: 'speech-huddle',
              createdAt: later,
            ),
          ];
          messages.setMessages(parentEvents);
          await tester.pump();
          await tester.pump();
          expect(spoken, isEmpty);
          expect(
            find.text('Reading deploy logs'),
            threaded ? findsOneWidget : findsNothing,
          );

          messages.setMessages([
            ...parentEvents,
            _threadReply(
              id: 'agent-final',
              pubkey: _huddleAgentKey,
              content: 'Deploy is healthy.',
              rootId: 'speech-huddle',
              createdAt: later + 1,
              voiceFinal: true,
            ),
          ]);
          for (var i = 0; i < 5; i++) {
            await tester.pump();
          }
          expect(
            spoken,
            threaded
                ? ['/huddle/$_huddleChannelId/speech Deploy is healthy.']
                : isEmpty,
          );
          expect(nativeCalls.contains('play'), threaded);

          await tester.tap(find.byKey(const ValueKey('huddle-chat')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('huddle-chat-message-agent-final')),
            threaded ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const ValueKey('huddle-chat-message-agent-top-level')),
            findsNothing,
          );
          await tester.enterText(
            find.byType(TextField).last,
            'And the database?',
          );
          await tester.tap(find.byTooltip('Send message'));
          await tester.pump();
          await tester.pump();

          final chat = relay.events.last;
          expect(chat.content, 'And the database?');
          expect(chat.tags, contains(equals(const ['p', _huddleAgentKey])));
          expect(
            chat.tags.where((tag) => tag.first == 'e').toList(),
            threaded
                ? [
                    ['e', 'speech-huddle', '', 'reply'],
                  ]
                : isEmpty,
          );
          expect(chat.channelId, threaded ? _channelId : _huddleChannelId);
        }, () => client);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
