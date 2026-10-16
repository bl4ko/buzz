import 'package:flutter/material.dart';

import '../../../shared/theme/theme.dart';
import 'channel_tasks_provider.dart';
import 'thread_status.dart';

class ChannelTasksView extends StatefulWidget {
  const ChannelTasksView({
    super.key,
    required this.state,
    required this.canSetStatus,
    required this.onReact,
    required this.onDone,
    required this.onOpenThread,
  });

  final ChannelTasksState state;
  final bool canSetStatus;
  final Future<void> Function(String eventId, String emoji) onReact;
  final Future<void> Function(ThreadTask task) onDone;
  final ValueChanged<String> onOpenThread;

  @override
  State<ChannelTasksView> createState() => _ChannelTasksViewState();
}

class _ChannelTasksViewState extends State<ChannelTasksView> {
  bool _showDone = false;
  final Map<String, String> _decided = {};

  Future<void> _run(
    Future<void> Function() action,
    String failure, {
    VoidCallback? onSuccess,
  }) async {
    try {
      await action();
      if (mounted) onSuccess?.call();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(failure)));
      }
    }
  }

  void _decide(String eventId, String label) =>
      setState(() => _decided[eventId] = label);

  Widget _row(ThreadTask task) {
    final ask = task.ask;
    return ListTile(
      title: Text(task.title),
      subtitle: ask == null ? null : Text(ask.text),
      onTap: () => widget.onOpenThread(task.rootId),
      trailing: Wrap(
        spacing: Grid.xxs,
        children: [
          if (ask != null && _decided[ask.eventId] != null)
            Text(_decided[ask.eventId]!)
          else if (ask != null && widget.canSetStatus) ...[
            OutlinedButton(
              onPressed: () => _run(
                () => widget.onReact(ask.eventId, approveEmoji),
                "Couldn't send approval",
                onSuccess: () => _decide(ask.eventId, 'Approved'),
              ),
              child: const Text('✅'),
            ),
            OutlinedButton(
              onPressed: () => _run(
                () => widget.onReact(ask.eventId, denyEmoji),
                "Couldn't send denial",
                onSuccess: () => _decide(ask.eventId, 'Denied'),
              ),
              child: const Text('❌'),
            ),
          ],
          if (widget.canSetStatus && task.status != TaskStatus.done)
            TextButton(
              onPressed: () =>
                  _run(() => widget.onDone(task), "Couldn't close the task"),
              child: const Text('Done'),
            ),
        ],
      ),
    );
  }

  List<Widget> _section(String title, List<ThreadTask> tasks) => tasks.isEmpty
      ? const []
      : [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Grid.sm,
              Grid.sm,
              Grid.sm,
              Grid.xxs,
            ),
            child: Text(title, style: Theme.of(context).textTheme.labelLarge),
          ),
          for (final task in tasks) _row(task),
        ];

  @override
  Widget build(BuildContext context) {
    final groups = widget.state.groups;
    return ListView(
      children: [
        ..._section('Needs you', groups.needsYou),
        ..._section('In progress', groups.inProgress),
        ..._section('Blocked', groups.blocked),
        if (groups.done.isNotEmpty)
          TextButton(
            onPressed: () => setState(() => _showDone = !_showDone),
            child: Text('Done (${groups.done.length})'),
          ),
        if (_showDone)
          for (final task in groups.done) _row(task),
      ],
    );
  }
}
