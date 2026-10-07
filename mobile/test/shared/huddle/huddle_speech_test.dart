import 'dart:async';
import 'dart:convert';

import 'package:buzz/shared/huddle/huddle_speech.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nostr/nostr.dart' as nostr;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('buzz/huddle_speech');
  test(
    'completed recognition clears its status when a transcript is skipped',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      final statuses = <String>[];
      final transcripts = <String>[];
      final speech = HuddleSpeech(
        baseUrl: 'https://buzz.example',
        nsec: nostr.Keys.generate().nsec,
        channelId: 'child',
        turnEnd: Duration.zero,
        client: MockClient(
          (_) async => http.Response('{"text":"Hello Hermes"}', 200),
        ),
      );
      speech.onStatus = statuses.add;
      speech.onTranscript = transcripts.add;
      await speech.start();
      final delivered = Completer<void>();
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('audio', {
            'audio': Uint8List.fromList([1, 2]),
          }),
        ),
        (_) => delivered.complete(),
      );
      await delivered.future;
      await Future<void>.delayed(Duration.zero);
      expect(transcripts, ['Hello Hermes']);
      expect(statuses, ['Recognizing speech', 'Listening on this device']);
      await speech.stop();
      speech.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    },
  );
  test(
    'speech requests are signed and a stopped call cannot play a late reply',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      final response = Completer<http.Response>();
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://buzz.example/huddle/child/speech',
        );
        expect(jsonDecode(request.body), {
          'text': 'Hello',
          'voice': 'am_michael',
        });
        final header = request.headers['Authorization']!;
        expect(header.startsWith('Nostr '), isTrue);
        final auth =
            jsonDecode(utf8.decode(base64Decode(header.substring(6))))
                as Map<String, dynamic>;
        expect(auth['kind'], 27235);
        expect(auth['tags'], contains(equals(['u', request.url.toString()])));
        expect(auth['tags'], contains(equals(['method', 'POST'])));
        expect(
          (auth['tags'] as List).any((tag) => tag[0] == 'payload'),
          isTrue,
        );
        return response.future;
      });
      final speech = HuddleSpeech(
        baseUrl: 'https://buzz.example',
        nsec: nostr.Keys.generate().nsec,
        channelId: 'child',
        client: client,
      );
      await speech.start(agentName: 'Hermes');
      final pending = speech.speak('Hello', voiceId: 'am_michael');
      await Future<void>.delayed(Duration.zero);
      await speech.stop();
      response.complete(http.Response.bytes(Uint8List.fromList([1, 2]), 200));
      await pending;
      expect(calls.map((call) => call.method), ['start', 'stop']);
      speech.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );

  test(
    'reply playback is ordered and old disposal preserves the new handler',
    () async {
      final finish = Completer<void>();
      var plays = 0;
      var requests = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'play') {
          plays++;
          if (plays == 1) await finish.future;
        }
        return null;
      });
      HuddleSpeech makeSpeech() => HuddleSpeech(
        baseUrl: 'https://buzz.example',
        nsec: nostr.Keys.generate().nsec,
        channelId: 'child',
        client: MockClient((request) async {
          requests++;
          return http.Response.bytes([1, 2], 200);
        }),
      );
      final old = makeSpeech();
      await old.start();
      final speech = makeSpeech();
      await speech.start();
      old.dispose();
      final status = Completer<String>();
      speech.onStatus = (message) {
        if (!status.isCompleted) status.complete(message);
      };
      const codec = StandardMethodCodec();
      final delivery = Completer<void>();
      messenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(
          const MethodCall('status', {'message': 'Listening'}),
        ),
        (_) => delivery.complete(),
      );
      await delivery.future;
      expect(await status.future, 'Listening');
      final first = speech.speak('First');
      final second = speech.speak('Second');
      await Future<void>.delayed(Duration.zero);
      expect(requests, 1);
      expect(plays, 1);
      finish.complete();
      await Future.wait([first, second]);
      expect(requests, 2);
      expect(plays, 2);
      await speech.stop();
      speech.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    },
  );

  test('stopping agent speech drops replies queued behind it', () async {
    final finish = Completer<void>();
    final calls = <String>[];
    var requests = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'play') await finish.future;
      if (call.method == 'stopPlayback' && !finish.isCompleted) {
        finish.complete();
      }
      return null;
    });
    final speech = HuddleSpeech(
      baseUrl: 'https://buzz.example',
      nsec: nostr.Keys.generate().nsec,
      channelId: 'child',
      client: MockClient((_) async {
        requests++;
        return http.Response.bytes([1, 2], 200);
      }),
    );
    await speech.start();
    final first = speech.speak('First');
    final second = speech.speak('Second');
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['start', 'play']);
    await speech.stopSpeaking();
    await Future.wait([first, second]);
    expect(requests, 1);
    expect(calls, ['start', 'play', 'stopPlayback']);
    final third = speech.speak('Third');
    await third;
    expect(requests, 2);
    expect(calls.last, 'play');
    await speech.stop();
    speech.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('user speech activity lasts until its turn is sent', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final texts = ['', 'Hello Hermes'];
    final speech = HuddleSpeech(
      baseUrl: 'https://buzz.example',
      nsec: nostr.Keys.generate().nsec,
      channelId: 'child',
      turnEnd: Duration.zero,
      client: MockClient(
        (_) async =>
            http.Response(jsonEncode({'text': texts.removeAt(0)}), 200),
      ),
    );
    final activity = <bool>[];
    speech.userSpeaking.addListener(
      () => activity.add(speech.userSpeaking.value),
    );
    final transcripts = <String>[];
    speech.onTranscript = transcripts.add;
    await speech.start();
    Future<void> send(String method, Object arguments) {
      final delivered = Completer<void>();
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (_) => delivered.complete(),
      );
      return delivered.future;
    }

    for (final _ in texts.toList()) {
      await send('speaking', {'speaking': true});
      expect(speech.userSpeaking.value, isTrue);
      await send('audio', {
        'audio': Uint8List.fromList([1, 2]),
      });
      await Future<void>.delayed(Duration.zero);
      expect(speech.userSpeaking.value, isFalse);
    }
    expect(transcripts, ['Hello Hermes']);
    expect(activity, [true, false, true, false]);
    await speech.stop();
    speech.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('a pause inside one sentence becomes one transcript', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final first = Completer<http.Response>();
    final replies = [
      first.future,
      Future.value(http.Response('{"text":"a table"}', 200)),
      Future.value(http.Response('{"text":"for two."}', 200)),
      Future.value(http.Response('{"text":"At eight."}', 200)),
    ];
    final transcripts = <String>[];
    final speech = HuddleSpeech(
      baseUrl: 'https://buzz.example',
      nsec: nostr.Keys.generate().nsec,
      channelId: 'child',
      turnEnd: const Duration(milliseconds: 100),
      client: MockClient((_) => replies.removeAt(0)),
    );
    speech.onTranscript = transcripts.add;
    await speech.start();
    Future<void> send(String method, Map<String, Object> arguments) {
      final delivered = Completer<void>();
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (_) => delivered.complete(),
      );
      return delivered.future;
    }

    final audio = {
      'audio': Uint8List.fromList([1, 2]),
    };
    final firstClip = send('audio', audio);
    await send('speaking', {'speaking': true});
    first.complete(http.Response('{"text":"Book"}', 200));
    await firstClip;
    expect(transcripts, isEmpty);
    await send('audio', audio);
    await send('speaking', {'speaking': true});
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(transcripts, isEmpty);
    await send('audio', audio);
    expect(transcripts, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(transcripts, ['Book a table for two.']);
    await send('speaking', {'speaking': true});
    await send('speaking', {'speaking': false});
    await send('audio', audio);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(transcripts, ['Book a table for two.', 'At eight.']);
    await speech.stop();
    speech.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('agent speech waits until the user stops speaking', () async {
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    final speech = HuddleSpeech(
      baseUrl: 'https://buzz.example',
      nsec: nostr.Keys.generate().nsec,
      channelId: 'child',
      client: MockClient((_) async => http.Response.bytes([1, 2], 200)),
    );
    await speech.start();
    final delivered = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('speaking', {'speaking': true}),
      ),
      (_) => delivered.complete(),
    );
    await delivered.future;
    final reply = speech.speak('Hello');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(calls, ['start']);
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('speaking', {'speaking': false}),
      ),
      null,
    );
    await reply;
    expect(calls, ['start', 'play']);
    await speech.stop();
    speech.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('room noise that never stops cannot hold speech forever', () async {
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    final transcripts = <String>[];
    final speech = HuddleSpeech(
      baseUrl: 'https://buzz.example',
      nsec: nostr.Keys.generate().nsec,
      channelId: 'child',
      turnEnd: Duration.zero,
      turnHold: const Duration(milliseconds: 300),
      client: MockClient(
        (request) async => request.url.path.endsWith('speech')
            ? http.Response.bytes([1, 2], 200)
            : http.Response('{"text":"Hello Hermes"}', 200),
      ),
    );
    speech.onTranscript = transcripts.add;
    await speech.start();
    Future<void> send(String method, Map<String, Object> arguments) {
      final delivered = Completer<void>();
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (_) => delivered.complete(),
      );
      return delivered.future;
    }

    await send('audio', {
      'audio': Uint8List.fromList([1, 2]),
    });
    await send('speaking', {'speaking': true});
    final reply = speech.speak('Hello');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(transcripts, isEmpty);
    expect(calls, ['start']);
    await reply;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(transcripts, ['Hello Hermes']);
    expect(calls, ['start', 'play']);
    await speech.stop();
    speech.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('a slow agent gets spoken cues until its reply arrives', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final spoken = <String>[];
    final speech = HuddleSpeech(
      baseUrl: 'https://buzz.example',
      nsec: nostr.Keys.generate().nsec,
      channelId: 'child',
      firstCue: const Duration(milliseconds: 50),
      nextCue: const Duration(milliseconds: 100),
      client: MockClient((request) async {
        spoken.add(jsonDecode(request.body)['text'] as String);
        return http.Response.bytes([1, 2], 200);
      }),
    );
    await speech.start();
    speech.awaitReply();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(spoken, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(spoken, ['One moment.', 'Still working.']);
    await speech.speak('Answer.');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(spoken, ['One moment.', 'Still working.', 'Answer.']);
    speech.awaitReply();
    await speech.stopSpeaking();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(spoken.length, 3);
    await speech.stop();
    speech.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('replies are spoken as plain sentence groups', () {
    final chunks = speechChunks(
      'Done. See **the report** at https://x.example/r and [notes](https://n). '
      '```\ncode\n``` ${'word ' * 80}End.',
    );
    expect(chunks.first, 'Done.');
    expect(chunks[1], startsWith('See the report at link and notes. word'));
    expect(chunks.every((chunk) => chunk.length <= 300), isTrue);
    expect(chunks.join(' '), isNot(contains('code')));
    expect(chunks.last, endsWith('End.'));
    expect(speechChunks('  **  '), isEmpty);
  });
}
