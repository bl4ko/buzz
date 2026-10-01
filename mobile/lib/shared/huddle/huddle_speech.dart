import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../relay/relay_session.dart';

final class HuddleSpeech {
  static HuddleSpeech? _owner;
  Future<void> _playback = Future.value();
  final MethodChannel _channel = const MethodChannel('buzz/huddle_speech');
  final http.Client _client;
  final String baseUrl;
  final String? nsec;
  final String channelId;
  void Function(String)? onTranscript;
  void Function(String)? onError;
  void Function(String)? onStatus;
  int _generation = 0;
  bool _transcribing = false;
  bool _active = false;
  String? _agentName;
  Uint8List? _pendingAudio;

  HuddleSpeech({
    required this.baseUrl,
    required this.nsec,
    required this.channelId,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<void> _handleCall(MethodCall call) async {
    if (!identical(_owner, this)) return;
    final values = call.arguments as Map?;
    if (call.method == 'audio' && values?['audio'] is Uint8List) {
      await _transcribe(values!['audio'] as Uint8List);
    } else if (call.method == 'error') {
      final message = values?['message'];
      if (message is String && message.trim().isNotEmpty) {
        onError?.call(message);
      }
    } else if (call.method == 'status' && values?['message'] is String) {
      if (_active) onStatus?.call(values!['message'] as String);
    }
  }

  Future<http.Response> _post(String path, Map<String, Object?> payload) async {
    final url = Uri.parse(baseUrl).resolve('/huddle/$channelId/$path');
    final bytes = utf8.encode(jsonEncode(payload));
    final response = await _client
        .post(
          url,
          headers: {
            'Authorization': buildNip98AuthHeader(
              method: 'POST',
              url: url.toString(),
              bodyBytes: bytes,
              nsec: nsec,
            ),
            'Content-Type': 'application/json',
          },
          body: bytes,
        )
        .timeout(const Duration(seconds: 65));
    if (response.statusCode != 200) {
      throw Exception(
        'Speech service ${response.statusCode}: ${response.body}',
      );
    }
    return response;
  }

  Future<void> _transcribe(Uint8List audio) async {
    if (!_active) return;
    if (_transcribing) {
      if (_pendingAudio != null) {
        onError?.call(
          'Speech service is busy. Please repeat your last sentence.',
        );
      } else {
        _pendingAudio = audio;
      }
      return;
    }
    _transcribing = true;
    final generation = _generation;
    onStatus?.call('Recognizing speech');
    try {
      final response = await _post('transcribe', {
        'audio': base64Encode(audio),
        'agent_name': _agentName,
      });
      if (!_active || generation != _generation) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final text = (data['text'] as String).trim();
      onStatus?.call('Listening on this device');
      if (text.isNotEmpty) {
        onTranscript?.call(text);
      }
    } catch (error) {
      if (_active && generation == _generation) {
        onError?.call('Could not recognize speech: $error');
      }
    } finally {
      _transcribing = false;
      final pending = _pendingAudio;
      _pendingAudio = null;
      if (_active && pending != null) {
        await _transcribe(pending);
      }
    }
  }

  Future<void> start({String? agentName}) async {
    _generation++;
    _pendingAudio = null;
    _agentName = agentName;
    _owner = this;
    _channel.setMethodCallHandler(_handleCall);
    await _channel.invokeMethod<void>('start', {'agentName': agentName});
    _active = true;
  }

  Future<void> stop() {
    _generation++;
    _active = false;
    _pendingAudio = null;
    if (!identical(_owner, this)) return Future.value();
    return _channel.invokeMethod<void>('stop');
  }

  Future<List<HuddleVoice>> voices() async => const [
    HuddleVoice('am_michael', 'Michael'),
    HuddleVoice('bm_george', 'George'),
    HuddleVoice('af_heart', 'Heart'),
  ];

  Future<void> speak(String text, {String? voiceId}) {
    final generation = _generation;
    final task = _playback.then((_) => _speak(text, voiceId, generation));
    _playback = task.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return task;
  }

  Future<void> _speak(String text, String? voiceId, int generation) async {
    if (!_active || generation != _generation || text.trim().isEmpty) return;
    onStatus?.call('Preparing voice');
    final response = await _post('speech', {
      'text': text,
      'voice': const {'am_michael', 'bm_george', 'af_heart'}.contains(voiceId)
          ? voiceId
          : null,
    });
    if (!_active || generation != _generation) return;
    onStatus?.call('Agent speaking');
    await _channel.invokeMethod<void>('play', {'audio': response.bodyBytes});
  }

  void dispose() {
    _generation++;
    _active = false;
    onTranscript = null;
    onError = null;
    onStatus = null;
    _client.close();
    if (identical(_owner, this)) {
      _owner = null;
      _channel.setMethodCallHandler(null);
    }
  }
}

final class HuddleVoice {
  final String id;
  final String name;
  const HuddleVoice(this.id, this.name);
}
