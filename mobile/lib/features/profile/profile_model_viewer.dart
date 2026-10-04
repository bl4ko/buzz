import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../shared/relay/relay.dart';
import 'profile_model_validation.dart';

class ProfileModelViewer extends HookConsumerWidget {
  const ProfileModelViewer({super.key, required this.url});
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(relayConfigProvider);
    final auth = ref.watch(mediaGetAuthServiceProvider);
    final client = ref.watch(mediaHttpClientProvider);
    final retry = useState(0);
    final load = useMemoized(() {
      var disposed = false;
      Directory? directory;
      Future<String> fetch() async {
        try {
          final uri = Uri.parse(url);
          if (uri.scheme != 'https' &&
              !(uri.scheme == 'http' &&
                  ['localhost', '127.0.0.1', '::1'].contains(uri.host))) {
            throw const FormatException('Model URL must use HTTPS.');
          }
          final request = http.Request('GET', uri)
            ..headers.addAll(auth.headersFor(url));
          final response = await client
              .send(request)
              .timeout(const Duration(seconds: 30));
          if (response.statusCode != 200) {
            await response.stream.listen((_) {}).cancel();
            throw HttpException(
              'Model download failed (${response.statusCode}).',
            );
          }
          final bytes = BytesBuilder(copy: false);
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 30),
          )) {
            if (disposed) throw StateError('Model viewer closed.');
            if (bytes.length + chunk.length > 20 * 1024 * 1024) {
              throw const FormatException('Model limit is 20 MB.');
            }
            bytes.add(chunk);
          }
          final data = bytes.takeBytes();
          validateProfileModel(data);
          final temporary = await getTemporaryDirectory();
          directory = await temporary.createTemp('buzz-profile-model-');
          final file = File('${directory!.path}/model.glb');
          await file.writeAsBytes(data, flush: true);
          if (disposed) throw StateError('Model viewer closed.');
          return file.uri.toString();
        } catch (_) {
          if (directory != null && await directory!.exists()) {
            await directory!.delete(recursive: true);
          }
          rethrow;
        }
      }

      return (
        future: fetch(),
        dispose: () {
          disposed = true;
          final current = directory;
          if (current != null) {
            unawaited(
              current.delete(recursive: true).catchError((Object _) => current),
            );
          }
        },
      );
    }, [url, config, retry.value]);
    useEffect(() => load.dispose, [load]);
    final snapshot = useFuture(load.future);
    if (snapshot.hasError) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Model could not load.'),
          TextButton(
            onPressed: () => retry.value++,
            child: const Text('Retry'),
          ),
        ],
      );
    }
    final source = snapshot.data;
    if (source == null) return const Center(child: CircularProgressIndicator());
    return ModelViewer(
      key: ValueKey(source),
      src: source,
      alt: 'Profile 3D model. Drag to rotate.',
      cameraControls: true,
      ar: false,
      debugLogging: false,
    );
  }
}
