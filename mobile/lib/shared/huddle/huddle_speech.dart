import 'package:flutter/services.dart';

final class HuddleSpeech {
  final MethodChannel _channel = const MethodChannel('buzz/huddle_speech');
  void Function(String)? onTranscript;
  void Function(String)? onError;

  HuddleSpeech() {
    _channel.setMethodCallHandler((call) async {
      final values = call.arguments as Map?;
      if (call.method == 'transcript') {
        final text = values?['text'];
        if (text is String && text.trim().isNotEmpty) {
          onTranscript?.call(text.trim());
        }
      } else if (call.method == 'error') {
        final message = values?['message'];
        if (message is String && message.trim().isNotEmpty) {
          onError?.call(message.trim());
        }
      }
    });
  }

  Future<void> start() => _channel.invokeMethod<void>('start');
  Future<void> stop() => _channel.invokeMethod<void>('stop');
  Future<List<HuddleVoice>> voices() async {
    final values = await _channel.invokeMethod<List<dynamic>>('voices') ?? [];
    return [
      for (final value in values)
        if (value is Map && value['id'] is String && value['name'] is String)
          HuddleVoice(value['id'] as String, value['name'] as String),
    ];
  }

  Future<void> speak(String text, {String? voiceId}) =>
      _channel.invokeMethod<void>('speak', {'text': text, 'voiceId': voiceId});

  void dispose() {
    onTranscript = null;
    onError = null;
    _channel.setMethodCallHandler(null);
  }
}

final class HuddleVoice {
  final String id;
  final String name;
  const HuddleVoice(this.id, this.name);
}
