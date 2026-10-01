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
}
