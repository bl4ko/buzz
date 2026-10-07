import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/profile/user_profile.dart';
import '../../shared/relay/relay.dart';
import 'profile_provider.dart';
import 'profile_model_viewer.dart';
import 'profile_model_validation.dart';

enum _MediaKind { icon, banner, model }

class ProfileMedia extends StatelessWidget {
  const ProfileMedia({
    super.key,
    this.bannerUrl,
    this.modelUrl,
    this.showBanner = true,
  });

  final bool showBanner;
  final String? bannerUrl;
  final String? modelUrl;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showBanner) ProfileBanner(url: bannerUrl),
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

class ProfileBanner extends StatelessWidget {
  const ProfileBanner({super.key, this.url});

  final String? url;

  @override
  Widget build(BuildContext context) => url?.isNotEmpty == true
      ? ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: double.infinity,
            height: 120,
            child: MediaImage(
              url: url!,
              fit: BoxFit.cover,
              semanticLabel: 'Profile banner',
              errorBuilder: (_, _, _) =>
                  const Center(child: Text('Banner could not load.')),
            ),
          ),
        )
      : const SizedBox.shrink();
}

class ProfileMediaEditor extends HookConsumerWidget {
  const ProfileMediaEditor({
    super.key,
    required this.profile,
    this.agentPubkey,
    this.onSaved,
  });

  final UserProfile? profile;
  final String? agentPubkey;
  final VoidCallback? onSaved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banner = useState(profile?.bannerUrl ?? '');
    final model = useState(profile?.modelUrl ?? '');
    final icon = useState(profile?.avatarUrl ?? '');
    final saved = useState((
      profile?.bannerUrl ?? '',
      profile?.modelUrl ?? '',
      profile?.avatarUrl ?? '',
    ));
    final busy = useState(false);
    final error = useState<String?>(null);
    final generation = useRef(0);
    final config = ref.watch(relayConfigProvider);
    final uploadService = ref.watch(mediaUploadServiceProvider);
    useEffect(
      () {
        generation.value++;
        banner.value = profile?.bannerUrl ?? '';
        model.value = profile?.modelUrl ?? '';
        icon.value = profile?.avatarUrl ?? '';
        saved.value = (banner.value, model.value, icon.value);
        busy.value = false;
        return () {
          generation.value++;
        };
      },
      [
        config,
        profile?.pubkey,
        profile?.bannerUrl,
        profile?.modelUrl,
        profile?.avatarUrl,
      ],
    );

    Future<void> pick(_MediaKind kind) async {
      final isModel = kind == _MediaKind.model;
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
                    label: 'Profile image',
                    extensions: ['gif', 'jpg', 'jpeg', 'png', 'webp'],
                    uniformTypeIdentifiers: ['public.image'],
                  ),
          ],
        );
        if (file == null) return;
        if (await file.length() > (isModel ? 50 : 10) * 1024 * 1024) {
          throw FormatException(
            isModel ? 'Model limit is 50 MB.' : 'Image limit is 10 MB.',
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
        } else if (kind == _MediaKind.icon) {
          icon.value = result.url;
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
        banner.value != saved.value.$1 ||
        model.value != saved.value.$2 ||
        icon.value != saved.value.$3;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Icon, banner and 3D model',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text(
              'Icon or banner image: 10 MB. Self-contained GLB model: 50 MB.',
            ),
            if (icon.value.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: ClipOval(
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: MediaImage(
                      url: icon.value,
                      fit: BoxFit.cover,
                      semanticLabel: 'Profile icon preview',
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.person_outline),
                    ),
                  ),
                ),
              ),
            ProfileMedia(bannerUrl: banner.value, modelUrl: model.value),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: disabled ? null : () => pick(_MediaKind.icon),
                  child: const Text('Upload icon'),
                ),
                if (icon.value.isNotEmpty)
                  TextButton(
                    onPressed: disabled ? null : () => icon.value = '',
                    child: const Text('Remove icon'),
                  ),
                TextButton(
                  onPressed: disabled ? null : () => pick(_MediaKind.banner),
                  child: const Text('Upload banner'),
                ),
                if (banner.value.isNotEmpty)
                  TextButton(
                    onPressed: disabled ? null : () => banner.value = '',
                    child: const Text('Remove banner'),
                  ),
                TextButton(
                  onPressed: disabled ? null : () => pick(_MediaKind.model),
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
                                avatarUrl: icon.value != saved.value.$3
                                    ? icon.value
                                    : null,
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
                                avatarUrl: icon.value != saved.value.$3
                                    ? icon.value
                                    : null,
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
                              saved.value = (
                                banner.value,
                                model.value,
                                icon.value,
                              );
                              onSaved?.call();
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
