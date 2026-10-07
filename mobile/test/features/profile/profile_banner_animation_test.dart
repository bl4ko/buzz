import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:buzz/features/profile/profile_media.dart';
import 'package:buzz/shared/relay/media_auth.dart';
import 'package:buzz/shared/relay/media_image.dart';
import 'package:buzz/shared/relay/media_upload.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:nostr/nostr.dart' as nostr;

void main() {
  test('banner selector accepts GIF files', () {
    expect(
      File('lib/features/profile/profile_media.dart').readAsStringSync(),
      contains("extensions: ['gif', 'jpg', 'jpeg', 'png', 'webp']"),
    );
  });

  testWidgets('uploaded GIF banner keeps its frames, timing and animation', (
    tester,
  ) async {
    final first = image.Image(width: 2, height: 1, frameDuration: 100);
    image.fill(first, color: image.ColorRgb8(255, 0, 0));
    final second = image.Image(width: 2, height: 1, frameDuration: 100);
    image.fill(second, color: image.ColorRgb8(0, 0, 255));
    first.addFrame(second);
    final gif = image.encodeGif(first);
    final url = 'https://relay.example/media/banner.gif';
    Uint8List? uploaded;
    final client = MockClient((request) async {
      if (request.method == 'PUT') {
        expect(request.headers['Content-Type'], 'image/gif');
        uploaded = request.bodyBytes;
        return http.Response(
          jsonEncode({
            'url': url,
            'sha256': 'a' * 64,
            'size': uploaded!.length,
            'type': 'image/gif',
            'uploaded': 1,
          }),
          200,
        );
      }
      expect(request.url.toString(), url);
      return http.Response.bytes(uploaded!, 200);
    });
    addTearDown(client.close);
    final service = MediaUploadService(
      baseUrl: 'https://relay.example',
      nsec: nostr.Keys.generate().nsec,
      pickGalleryImage: () async => null,
      pickGalleryVideo: () async => null,
      httpClient: client,
    );
    final result = await service.uploadImage(
      XFile.fromData(gif, name: 'banner.gif'),
    );
    expect(result.type, 'image/gif');
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(uploaded!);
      expect(codec.frameCount, 2);
      expect(codec.repetitionCount, -1);
      for (var frame = 0; frame < 2; frame++) {
        final decoded = await codec.getNextFrame();
        expect(decoded.duration, const Duration(milliseconds: 100));
        decoded.image.dispose();
      }
      codec.dispose();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaGetAuthServiceProvider.overrideWithValue(
            MediaGetAuthService(baseUrl: 'https://relay.example', nsec: null),
          ),
          mediaHttpClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
          home: Scaffold(body: ProfileBanner(url: result.url)),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    final firstFrame = tester.widget<RawImage>(find.byType(RawImage)).image;
    expect(firstFrame, isNotNull);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump(const Duration(milliseconds: 150));
    final nextFrame = tester.widget<RawImage>(find.byType(RawImage)).image;
    expect(nextFrame, isNot(same(firstFrame)));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
