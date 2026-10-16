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
  final Map<String, OwnerDecision> _decided = {};
  final Set<String> _pending = {};

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

  Future<void> _send(String eventId, OwnerDecision decision) async {
    setState(() => _pending.add(eventId));
    await _run(
      () => widget.onReact(
        eventId,
        decision == OwnerDecision.approve ? approveEmoji : denyEmoji,
      ),
      decision == OwnerDecision.approve
          ? "Couldn't send approval"
          : "Couldn't send denial",
      onSuccess: () => _decided[eventId] = decision,
    );
    if (mounted) setState(() => _pending.remove(eventId));
  }

  Widget _row(ThreadTask task) {
    final ask = task.ask;
    final decision = ask == null
        ? null
        : widget.state.decisions[ask.eventId] ?? _decided[ask.eventId];
    final pending = ask != null && _pending.contains(ask.eventId);
    return ListTile(
      title: Text(task.title),
      subtitle: ask == null ? null : Text(ask.text),
      onTap: () => widget.onOpenThread(task.rootId),
      trailing: Wrap(
        spacing: Grid.xxs,
        children: [
          if (decision != null)
            Text(decision == OwnerDecision.approve ? 'Approved' : 'Denied')
          else if (ask != null && widget.canSetStatus) ...[
            OutlinedButton(
              onPressed: pending
                  ? null
                  : () => _send(ask.eventId, OwnerDecision.approve),
              child: const Text('✅'),
            ),
            OutlinedButton(
              onPressed: pending
                  ? null
                  : () => _send(ask.eventId, OwnerDecision.deny),
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
