part of '../channel_detail_page_test.dart';

typedef _IphoneHuddleCall = ({
  List<String> nativeCalls,
  _FakeMessagesNotifier messages,
  NostrEvent start,
  int later,
});

Future<void> _withIphoneHuddleCall(
  WidgetTester tester, {
  required Size size,
  required Future<void> Function(_IphoneHuddleCall call) body,
  EdgeInsets padding = EdgeInsets.zero,
  String transcript = 'Check the deploy',
  Future<void>? playback,
}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = FakeViewPadding(
    top: padding.top * 3,
    bottom: padding.bottom * 3,
  );
  addTearDown(tester.view.reset);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final nativeCalls = <String>[];
  messenger.setMockMethodCallHandler(_speechChannel, (call) async {
    nativeCalls.add(call.method);
    if (call.method == 'play') await playback;
    return call.method == 'microphoneMode' ? 'voiceIsolation' : null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(_speechChannel, null));
  final client = http_testing.MockClient((request) async {
    if (request.url.path.endsWith('/transcribe')) {
      return http.Response(jsonEncode({'text': transcript}), 200);
    }
    return http.Response.bytes(const [1, 2, 3], 200);
  });
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final start = _huddleMsg(
    id: 'layout-huddle',
    kind: EventKind.huddleStarted,
    pubkey: 'self',
    createdAt: now,
    chatInThread: true,
  );
  final messages = _FakeMessagesNotifier([start]);
  final agent = ChannelMember(
    pubkey: 'agent',
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
          'agent': UserProfile(pubkey: 'agent', displayName: 'Pollen'),
          'self': UserProfile(pubkey: 'self', displayName: 'Self'),
        }),
        threadReplies: {'layout-huddle': const []},
        relayConfigNotifier: _HuddleRelayConfigNotifier(),
        huddleCurrentPubkey: 'self',
        huddleHumanCountLoader: (_) async => 2,
        huddleMediaFactory: _HuddleTestMedia.new,
        huddleTransportFactory: (_) => _HuddleTestTransport(
          peers: const {
            1: HuddlePeer(pubkey: 'self', peerIndex: 1, epoch: 0),
            2: HuddlePeer(pubkey: 'agent', peerIndex: 2, epoch: 0),
          },
        ),
        sendMessage: _recordingSendMessage(_PublishedEvents()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pumpAndSettle();
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
    await body((
      nativeCalls: nativeCalls,
      messages: messages,
      start: start,
      later: now + 60,
    ));
  }, () => client);
  debugDefaultTargetPlatformOverride = null;
}

Future<void> _pumpAgentReplies(
  WidgetTester tester,
  _IphoneHuddleCall call,
  List<NostrEvent> replies,
) async {
  call.messages.setMessages([call.start, ...replies]);
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

Finder _huddleLine(String key) => find.byKey(ValueKey(key));

Finder _semanticsLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

void huddleCallLayoutTests() {
  testWidgets('iPhone huddle shows the latest final agent reply', (
    tester,
  ) async {
    await _withIphoneHuddleCall(
      tester,
      size: const Size(390, 844),
      body: (call) async {
        expect(
          find.text('You: Check the deploy', findRichText: true),
          findsOneWidget,
        );
        expect(_huddleLine('huddle-agent-voice-reply'), findsNothing);

        await _pumpAgentReplies(tester, call, [
          _threadReply(
            id: 'agent-first',
            pubkey: 'agent',
            content: 'Looking at it.',
            rootId: 'layout-huddle',
            createdAt: call.later,
            voiceFinal: true,
          ),
          _threadReply(
            id: 'agent-final',
            pubkey: 'agent',
            content: 'Deploy is healthy.',
            rootId: 'layout-huddle',
            createdAt: call.later + 1,
            voiceFinal: true,
          ),
          _threadReply(
            id: 'agent-progress',
            pubkey: 'agent',
            content: 'Reading more logs',
            rootId: 'layout-huddle',
            createdAt: call.later + 2,
          ),
          _textMsg(
            id: 'agent-top-level',
            pubkey: 'agent',
            content: 'Unrelated channel report.',
            createdAt: call.later + 3,
            extraTags: const [
              ['voice', 'final'],
            ],
          ),
        ]);

        expect(
          find.text('Pollen: Deploy is healthy.', findRichText: true),
          findsOneWidget,
        );
        expect(
          find.textContaining('Looking at it.', findRichText: true),
          findsNothing,
        );
        expect(
          find.textContaining('Unrelated channel report.', findRichText: true),
          findsNothing,
        );
        for (final key in [
          'huddle-agent-voice-heard',
          'huddle-agent-voice-reply',
        ]) {
          expect(tester.widget<Text>(_huddleLine(key)).maxLines, 4);
        }
        expect(
          tester.getTopLeft(_huddleLine('huddle-agent-voice-reply')).dy,
          greaterThan(
            tester.getBottomLeft(_huddleLine('huddle-agent-voice-heard')).dy -
                0.01,
          ),
        );
      },
    );
  });

  testWidgets('iPhone huddle agent controls share one compact row', (
    tester,
  ) async {
    await _withIphoneHuddleCall(
      tester,
      size: const Size(390, 844),
      padding: const EdgeInsets.only(top: 47, bottom: 34),
      playback: Completer<void>().future,
      body: (call) async {
        await _pumpAgentReplies(tester, call, [
          _threadReply(
            id: 'agent-final',
            pubkey: 'agent',
            content: 'Deploy is healthy.',
            rootId: 'layout-huddle',
            createdAt: call.later,
            voiceFinal: true,
          ),
        ]);
        expect(call.nativeCalls, contains('play'));

        const voice = ValueKey('huddle-agent-voice');
        const micMode = ValueKey('huddle-agent-mic-mode');
        const stop = ValueKey('huddle-agent-stop-speaking');
        final toolbar = find.byKey(const ValueKey('huddle-agent-toolbar'));
        for (final key in [voice, micMode, stop]) {
          expect(
            find.descendant(of: toolbar, matching: find.byKey(key)),
            findsOneWidget,
          );
          final size = tester.getSize(find.byKey(key));
          expect(size.width, greaterThanOrEqualTo(44));
          expect(size.height, greaterThanOrEqualTo(44));
          expect(
            tester.getCenter(find.byKey(key)).dy,
            closeTo(tester.getCenter(toolbar).dy, 0.01),
          );
        }
        expect(tester.getSize(toolbar).height, lessThanOrEqualTo(48));
        expect(find.byType(OutlinedButton), findsNothing);
        expect(find.textContaining('Mic mode'), findsNothing);
        expect(find.text('Stop speaking'), findsNothing);
        expect(
          find.descendant(of: toolbar, matching: find.text('Pollen')),
          findsOneWidget,
        );
        expect(find.byTooltip('Mic mode: Voice Isolation'), findsOneWidget);
        expect(_semanticsLabel('Mic mode: Voice Isolation'), findsOneWidget);
        final micButton = tester.widget<IconButton>(
          find.descendant(
            of: find.byKey(micMode),
            matching: find.byType(IconButton),
          ),
        );
        final colors = Theme.of(tester.element(toolbar)).colorScheme;
        expect(
          micButton.style!.backgroundColor!.resolve(const {}),
          colors.primary,
        );
        expect(_semanticsLabel('Stop speaking'), findsOneWidget);

        expect(
          tester.getTopLeft(toolbar).dy,
          greaterThan(
            tester
                .getBottomLeft(
                  find.byKey(const ValueKey('huddle-speaking-ring-self')),
                )
                .dy,
          ),
        );
        expect(
          tester.getTopLeft(_huddleLine('huddle-agent-voice-heard')).dy,
          greaterThan(tester.getBottomLeft(toolbar).dy),
        );
        expect(
          tester.getBottomLeft(_huddleLine('huddle-agent-voice-reply')).dy,
          lessThan(
            tester
                .getTopLeft(find.byKey(const ValueKey('huddle-call-controls')))
                .dy,
          ),
        );

        await tester.tap(find.byKey(micMode));
        await tester.pump();
        expect(call.nativeCalls, contains('showMicrophoneModes'));

        await tester.tap(find.byKey(stop));
        await tester.pump();
        expect(call.nativeCalls, contains('stopPlayback'));
        expect(find.byKey(stop), findsNothing);
        expect(find.byKey(micMode), findsOneWidget);
      },
    );
  });

  for (final (size, padding) in [
    (const Size(375, 667), const EdgeInsets.only(top: 20)),
    (const Size(390, 844), const EdgeInsets.only(top: 47, bottom: 34)),
  ]) {
    testWidgets(
      'iPhone huddle call fits ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        final words = List.filled(80, 'deploy').join(' ');
        await _withIphoneHuddleCall(
          tester,
          size: size,
          padding: padding,
          transcript: 'Check the $words',
          playback: Completer<void>().future,
          body: (call) async {
            await _pumpAgentReplies(tester, call, [
              _threadReply(
                id: 'agent-final',
                pubkey: 'agent',
                content: 'The $words is healthy.',
                rootId: 'layout-huddle',
                createdAt: call.later,
                voiceFinal: true,
              ),
            ]);
            expect(tester.takeException(), isNull);
            expect(
              find.byKey(const ValueKey('huddle-agent-stop-speaking')),
              findsOneWidget,
            );

            final screen = tester.view.physicalSize / 3;
            final controls = tester.getRect(
              find.byKey(const ValueKey('huddle-call-controls')),
            );
            expect(controls.bottom, lessThanOrEqualTo(screen.height));
            final conversation = tester.getRect(
              find.byKey(const ValueKey('huddle-agent-conversation')),
            );
            expect(conversation.bottom, lessThanOrEqualTo(controls.top));
            expect(
              conversation.top,
              greaterThanOrEqualTo(
                tester
                    .getRect(find.byKey(const ValueKey('huddle-agent-toolbar')))
                    .bottom,
              ),
            );
            for (final key in [
              'huddle-agent-voice-heard',
              'huddle-agent-voice-reply',
            ]) {
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(
                  of: _huddleLine(key),
                  matching: find.byType(RichText),
                ),
              );
              expect(paragraph.didExceedMaxLines, isTrue);
            }
            expect(
              tester.getTopLeft(_huddleLine('huddle-agent-voice-reply')).dy,
              lessThan(conversation.bottom),
            );
            await tester.drag(
              find.byKey(const ValueKey('huddle-agent-conversation')),
              const Offset(0, -400),
            );
            await tester.pump();
            expect(
              tester.getBottomLeft(_huddleLine('huddle-agent-voice-reply')).dy,
              lessThanOrEqualTo(conversation.bottom + 0.01),
            );

            final selfRing = tester.getRect(
              find.byKey(const ValueKey('huddle-speaking-ring-self')),
            );
            final stage = tester.getRect(
              find.byKey(const ValueKey('huddle-participant-stage')),
            );
            expect(selfRing.top, greaterThanOrEqualTo(stage.top));
            expect(selfRing.bottom, lessThanOrEqualTo(stage.bottom));
            final agentRing = tester.getRect(
              find.byKey(const ValueKey('huddle-speaking-ring-agent')),
            );
            expect(agentRing.size, selfRing.size);
            expect(agentRing.top, selfRing.top);
            expect(agentRing.left, greaterThan(selfRing.right - 1));
            expect(agentRing.right, lessThanOrEqualTo(stage.right));
            expect(agentRing.bottom, lessThanOrEqualTo(stage.bottom));
            expect(find.text('You'), findsOneWidget);
            expect(
              find.descendant(
                of: find.byKey(const ValueKey('huddle-participant-grid')),
                matching: find.text('Pollen'),
              ),
              findsOneWidget,
            );
          },
        );
      },
    );
  }
}
