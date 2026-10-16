import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/theme/theme.dart';
import 'canvas_doc.dart';
import 'canvas_doc_provider.dart';

class CanvasEditorPane extends StatelessWidget {
  const CanvasEditorPane({
    super.key,
    required this.draft,
    required this.onChanged,
    required this.conflictAuthor,
    required this.saving,
    required this.onSave,
    required this.onReload,
    required this.onOverwrite,
    required this.onCancel,
  });

  final String draft;
  final ValueChanged<String> onChanged;
  final String? conflictAuthor;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onReload;
  final VoidCallback onOverwrite;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final bytes = canvasBytes(draft);
    final tooLarge = bytes > canvasMaxBytes;
    return Column(
      children: [
        if (conflictAuthor != null)
          MaterialBanner(
            content: Text('Changed by $conflictAuthor. Reload or overwrite?'),
            actions: [
              TextButton(onPressed: onReload, child: const Text('Reload')),
              TextButton(
                onPressed: saving || tooLarge ? null : onOverwrite,
                child: const Text('Overwrite'),
              ),
            ],
          ),
        Expanded(
          child: TextFormField(
            initialValue: draft,
            maxLines: null,
            expands: true,
            onChanged: onChanged,
          ),
        ),
        Row(
          children: [
            Text('$bytes / $canvasMaxBytes bytes'),
            const Spacer(),
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
            FilledButton(
              onPressed: saving || tooLarge || conflictAuthor != null
                  ? null
                  : onSave,
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}

class CanvasDocView extends HookConsumerWidget {
  const CanvasDocView({
    super.key,
    required this.channelId,
    required this.canvasId,
    required this.canEdit,
  });

  final String channelId;
  final String canvasId;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (channelId, canvasId);
    final latest = ref.watch(canvasDocProvider(key));
    final editing = useState(false);
    final draft = useState('');
    final base = useState<String?>(null);
    final saving = useState(false);
    final conflict = editing.value ? canvasConflict(base.value, latest) : null;
    Future<void> save({required bool force}) async {
      saving.value = true;
      try {
        final result = await ref
            .read(canvasDocProvider(key).notifier)
            .save(draft.value, base.value, force: force);
        if (result == CanvasSaveResult.saved) editing.value = false;
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(SnackBar(content: Text('$error')));
        }
      } finally {
        saving.value = false;
      }
    }

    if (editing.value) {
      return CanvasEditorPane(
        key: ValueKey(base.value),
        draft: draft.value,
        onChanged: (value) => draft.value = value,
        conflictAuthor: conflict?.author.substring(0, 8),
        saving: saving.value,
        onSave: () => save(force: false),
        onReload: () {
          draft.value = latest?.content ?? '';
          base.value = latest?.eventId;
        },
        onOverwrite: () => save(force: true),
        onCancel: () => editing.value = false,
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(
        Grid.twelve,
        Grid.twelve,
        Grid.twelve,
        Grid.twelve + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        if (canEdit)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () {
                draft.value = latest?.content ?? '';
                base.value = latest?.eventId;
                editing.value = true;
              },
              child: const Text('Edit'),
            ),
          ),
        if ((latest?.content ?? '').isEmpty)
          const Text('This canvas is empty.')
        else
          GptMarkdown(latest!.content),
      ],
    );
  }
}
