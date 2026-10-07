import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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
  final Duration turnEnd;
  final Duration turnHold;
  final Duration firstCue;
  final Duration nextCue;
  final ValueNotifier<bool> agentSpeaking = ValueNotifier(false);
  final ValueNotifier<bool> userSpeaking = ValueNotifier(false);
  void Function(String)? onTranscript;
  void Function(String)? onError;
  void Function(String)? onStatus;
  int _generation = 0;
  int _playbackGeneration = 0;
  int _replies = 0;
  bool _transcribing = false;
  DateTime? _speakingSince;
  bool _active = false;
  Timer? _turnTimer;
  Timer? _cueTimer;
  String? _agentName;
  String _heard = '';
  final List<Uint8List> _clips = [];

  HuddleSpeech({
    required this.baseUrl,
    required this.nsec,
    required this.channelId,
    this.turnEnd = const Duration(milliseconds: 500),
    this.turnHold = const Duration(seconds: 3),
    this.firstCue = const Duration(seconds: 4),
    this.nextCue = const Duration(seconds: 20),
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<void> _handleCall(MethodCall call) async {
    if (!identical(_owner, this)) return;
    final values = call.arguments as Map?;
    if (call.method == 'audio' && values?['audio'] is Uint8List) {
      _speakingSince = null;
      if (!_active) return;
      if (_clips.length >= 4) {
        onError?.call('Speech service is busy. Please repeat your sentence.');
        return;
      }
      _clips.add(values!['audio'] as Uint8List);
      _turnTimer?.cancel();
      _turnTimer = Timer(turnEnd, _flush);
      _syncUserSpeaking();
      await _drain();
    } else if (call.method == 'speaking' && values?['speaking'] is bool) {
      _speakingSince = values!['speaking'] as bool
          ? _speakingSince ?? DateTime.now()
          : null;
      _flush();
      _syncUserSpeaking();
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
    final http.Response response;
    try {
      response = await _client
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
    } on TimeoutException {
      throw const HuddleSpeechException('The speech service timed out.');
    } on http.ClientException {
      throw const HuddleSpeechException('Check the network connection.');
    }
    if (response.statusCode == 429) {
      throw const HuddleSpeechException('The speech service is busy.');
    }
    if (response.statusCode != 200) {
      debugPrint('[HuddleSpeech] $path ${response.statusCode}');
      throw HuddleSpeechException(
        'The speech service failed (${response.statusCode}).',
      );
    }
    return response;
  }

  Future<void> _drain() async {
    if (_transcribing) return;
    _transcribing = true;
    _syncUserSpeaking();
    final generation = _generation;
    var failed = false;
    try {
      while (_clips.isNotEmpty && _active && generation == _generation) {
        final clip = _clips.removeAt(0);
        onStatus?.call('Recognizing speech');
        try {
          final response = await _post('transcribe', {
            'audio': base64Encode(clip),
            'agent_name': _agentName,
          });
          if (!_active || generation != _generation) return;
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final text = (data['text'] as String).trim();
          if (text.isNotEmpty) _heard = _heard.isEmpty ? text : '$_heard $text';
          failed = false;
        } catch (error) {
          if (!_active || generation != _generation) return;
          failed = true;
          onError?.call('Could not recognize speech. ${_reason(error)}');
        }
      }
    } finally {
      _transcribing = false;
      _syncUserSpeaking();
    }
    if (!_active || generation != _generation) return;
    if (!failed) onStatus?.call('Listening on this device');
    _flush();
  }

  void _syncUserSpeaking() => userSpeaking.value =
      _active &&
      (_speakingSince != null ||
          _transcribing ||
          _clips.isNotEmpty ||
          _heard.isNotEmpty);

  Duration get _held => _speakingSince == null
      ? Duration.zero
      : turnHold - DateTime.now().difference(_speakingSince!);

  void _flush() {
    if (_transcribing ||
        _clips.isNotEmpty ||
        _heard.isEmpty ||
        (_turnTimer?.isActive ?? false)) {
      return;
    }
    if (_held > Duration.zero) {
      _turnTimer = Timer(_held, _flush);
      return;
    }
    final text = _heard;
    _heard = '';
    _syncUserSpeaking();
    onTranscript?.call(text);
  }

  Future<void> start({String? agentName}) async {
    _generation++;
    _cueTimer?.cancel();
    _clips.clear();
    _heard = '';
    _speakingSince = null;
    _agentName = agentName;
    _owner = this;
    _channel.setMethodCallHandler(_handleCall);
    await _channel.invokeMethod<void>('start', {'agentName': agentName});
    _active = true;
    _syncUserSpeaking();
  }

  Future<void> stop() {
    _generation++;
    _active = false;
    _turnTimer?.cancel();
    _cueTimer?.cancel();
    _clips.clear();
    _heard = '';
    _speakingSince = null;
    _syncUserSpeaking();
    if (!identical(_owner, this)) return Future.value();
    return _channel.invokeMethod<void>('stop');
  }

  Future<List<HuddleVoice>> voices() async => const [
    HuddleVoice('af_heart', 'Heart'),
    HuddleVoice('am_michael', 'Michael'),
    HuddleVoice('bm_george', 'George'),
  ];

  Future<void> stopSpeaking() async {
    _playbackGeneration++;
    _cueTimer?.cancel();
    agentSpeaking.value = false;
    await _channel.invokeMethod<void>('stopPlayback');
    if (_active) onStatus?.call('Listening on this device');
  }

  Future<String> microphoneMode() async =>
      await _channel.invokeMethod<String>('microphoneMode') ?? 'standard';

  Future<void> showMicrophoneModes() =>
      _channel.invokeMethod<void>('showMicrophoneModes');

  void awaitReply({String? voiceId}) {
    _cueTimer?.cancel();
    void cue(String text) {
      if (_active && _replies == 0 && _held <= Duration.zero) {
        unawaited(_enqueue(text, voiceId).catchError((Object _) {}));
      }
    }

    _cueTimer = Timer(firstCue, () {
      cue('One moment.');
      _cueTimer = Timer.periodic(nextCue, (_) => cue('Still working.'));
    });
  }

  Future<void> speak(String text, {String? voiceId}) {
    _cueTimer?.cancel();
    return _enqueue(text, voiceId);
  }

  Future<void> _enqueue(String text, String? voiceId) {
    final generation = _generation;
    final playback = _playbackGeneration;
    _replies++;
    agentSpeaking.value = true;
    final task = _playback
        .then((_) => _speak(text, voiceId, generation, playback))
        .whenComplete(() {
          _replies--;
          if (_replies == 0) agentSpeaking.value = false;
        });
    _playback = task.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return task;
  }

  Future<void> _speak(
    String text,
    String? voiceId,
    int generation,
    int playback,
  ) async {
    bool current() =>
        _active && generation == _generation && playback == _playbackGeneration;
    final chunks = speechChunks(text);
    if (!current() || chunks.isEmpty) return;
    onStatus?.call('Preparing voice');
    final voice =
        const {'am_michael', 'bm_george', 'af_heart'}.contains(voiceId)
        ? voiceId
        : null;
    Future<Uint8List> fetch(String chunk) => _post('speech', {
      'text': chunk,
      'voice': voice,
    }).then((response) => response.bodyBytes);
    Future<Uint8List>? next = fetch(chunks.first);
    try {
      for (var index = 0; index < chunks.length; index++) {
        final audio = await next!;
        next = index + 1 < chunks.length ? fetch(chunks[index + 1]) : null;
        while (_held > Duration.zero && current()) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (!current()) return;
        onStatus?.call('Agent speaking. Tap Stop speaking to talk.');
        await _channel.invokeMethod<void>('play', {'audio': audio});
        if (!current()) return;
      }
    } finally {
      next?.ignore();
    }
  }

  void dispose() {
    _generation++;
    _active = false;
    _turnTimer?.cancel();
    _cueTimer?.cancel();
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

String _reason(Object error) => error is HuddleSpeechException
    ? error.message
    : 'The speech service failed.';

/// Plain spoken text in sentence groups; the first group is short so audio starts early.
@visibleForTesting
List<String> speechChunks(String text, {int limit = 300}) {
  final plain = text
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAllMapped(
        RegExp(r'!?\[([^\]]*)\]\([^)]*\)'),
        (match) => match[1] ?? '',
      )
      .replaceAll(RegExp(r'https?://\S+'), 'link')
      .replaceAll(RegExp(r'[`*_#>|~]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final chunks = <String>[];
  var current = '';
  for (final sentence in plain.split(RegExp(r'(?<=[.!?])\s+'))) {
    for (final word in sentence.split(' ')) {
      if (current.isNotEmpty && current.length + word.length + 1 > limit) {
        chunks.add(current);
        current = '';
      }
      current = current.isEmpty ? word : '$current $word';
    }
    if (chunks.isEmpty || current.length > limit ~/ 2) {
      if (current.isNotEmpty) chunks.add(current);
      current = '';
    }
  }
  if (current.isNotEmpty) chunks.add(current);
  return chunks;
}

final class HuddleSpeechException implements Exception {
  final String message;
  const HuddleSpeechException(this.message);

  @override
  String toString() => message;
}

final class HuddleVoice {
  final String id;
  final String name;
  const HuddleVoice(this.id, this.name);
}
