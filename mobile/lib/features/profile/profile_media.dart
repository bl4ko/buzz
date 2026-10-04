import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/profile/user_profile.dart';
import '../../shared/relay/relay.dart';
import 'profile_provider.dart';
import 'profile_model_viewer.dart';
import 'profile_model_validation.dart';

class ProfileMedia extends StatelessWidget {
  const ProfileMedia({super.key, this.bannerUrl, this.modelUrl});

  final String? bannerUrl;
  final String? modelUrl;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (bannerUrl?.isNotEmpty == true)
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: MediaImage(
            url: bannerUrl!,
            height: 120,
            fit: BoxFit.cover,
            semanticLabel: 'Profile banner',
            errorBuilder: (_, _, _) => const Text('Banner could not load.'),
          ),
        ),
      if (modelUrl?.isNotEmpty == true)
        TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => Dialog(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Profile 3D model'),
                  ),
                  SizedBox(
                    height: 320,
                    child: ProfileModelViewer(url: modelUrl!),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
          child: const Text('View 3D model'),
        ),
    ],
  );
}

class ProfileMediaEditor extends HookConsumerWidget {
  const ProfileMediaEditor({
    super.key,
    required this.profile,
    this.agentPubkey,
  });

  final UserProfile? profile;
  final String? agentPubkey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banner = useState(profile?.bannerUrl ?? '');
    final model = useState(profile?.modelUrl ?? '');
    final saved = useState((profile?.bannerUrl ?? '', profile?.modelUrl ?? ''));
    final busy = useState(false);
    final error = useState<String?>(null);
    final generation = useRef(0);
    final config = ref.watch(relayConfigProvider);
    final uploadService = ref.watch(mediaUploadServiceProvider);
    useEffect(() {
      generation.value++;
      banner.value = profile?.bannerUrl ?? '';
      model.value = profile?.modelUrl ?? '';
      saved.value = (banner.value, model.value);
      busy.value = false;
      return () {
        generation.value++;
      };
    }, [config, profile?.pubkey, profile?.bannerUrl, profile?.modelUrl]);

    Future<void> pick(bool isModel) async {
      final current = ++generation.value;
      busy.value = true;
      error.value = null;
      try {
        final file = await openFile(
          acceptedTypeGroups: [
            isModel
                ? const XTypeGroup(
                    label: 'GLB model',
                    extensions: ['glb'],
                    uniformTypeIdentifiers: ['public.data'],
                  )
                : const XTypeGroup(
                    label: 'Banner image',
                    extensions: ['jpg', 'jpeg', 'png', 'webp'],
                    uniformTypeIdentifiers: ['public.image'],
                  ),
          ],
        );
        if (file == null) return;
        if (await file.length() > (isModel ? 20 : 10) * 1024 * 1024) {
          throw FormatException(
            isModel ? 'Model limit is 20 MB.' : 'Banner limit is 10 MB.',
          );
        }
        if (isModel) {
          validateProfileModel(await file.readAsBytes());
        }
        final result = isModel
            ? await uploadService.uploadFile(file)
            : await uploadService.uploadImage(file);
        if (!context.mounted || current != generation.value) return;
        if (isModel) {
          model.value = result.url;
        } else {
          banner.value = result.url;
        }
      } catch (cause) {
        if (context.mounted && current == generation.value) {
          error.value = cause.toString();
        }
      } finally {
        if (context.mounted && current == generation.value) busy.value = false;
      }
    }

    final disabled = busy.value || profile == null;
    final changed =
        banner.value != saved.value.$1 || model.value != saved.value.$2;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Banner and 3D model',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text('Banner image: 10 MB. Self-contained GLB model: 20 MB.'),
            ProfileMedia(bannerUrl: banner.value, modelUrl: model.value),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: disabled ? null : () => pick(false),
                  child: const Text('Upload banner'),
                ),
                if (banner.value.isNotEmpty)
                  TextButton(
                    onPressed: disabled ? null : () => banner.value = '',
                    child: const Text('Remove banner'),
                  ),
                TextButton(
                  onPressed: disabled ? null : () => pick(true),
                  child: const Text('Upload 3D model'),
                ),
                if (model.value.isNotEmpty)
                  TextButton(
                    onPressed: disabled ? null : () => model.value = '',
                    child: const Text('Remove model'),
                  ),
                FilledButton(
                  onPressed: disabled || !changed
                      ? null
                      : () async {
                          final current = ++generation.value;
                          busy.value = true;
                          error.value = null;
                          try {
                            final notifier = ref.read(profileProvider.notifier);
                            if (agentPubkey == null) {
                              await notifier.updateMedia(
                                bannerUrl: banner.value != saved.value.$1
                                    ? banner.value
                                    : null,
                                modelUrl: model.value != saved.value.$2
                                    ? model.value
                                    : null,
                              );
                            } else {
                              await notifier.updateAgentMedia(
                                agentPubkey: agentPubkey!,
                                bannerUrl: banner.value != saved.value.$1
                                    ? banner.value
                                    : null,
                                modelUrl: model.value != saved.value.$2
                                    ? model.value
                                    : null,
                              );
                            }
                            if (context.mounted &&
                                current == generation.value) {
                              saved.value = (banner.value, model.value);
                            }
                          } catch (cause) {
                            if (context.mounted &&
                                current == generation.value) {
                              error.value = cause.toString();
                            }
                          } finally {
                            if (context.mounted &&
                                current == generation.value) {
                              busy.value = false;
                            }
                          }
                        },
                  child: const Text('Save profile media'),
                ),
              ],
            ),
            if (busy.value) const Text('Saving…'),
            if (error.value != null)
              Text(error.value!, semanticsLabel: 'Error: ${error.value}'),
          ],
        ),
      ),
    );
  }
}
