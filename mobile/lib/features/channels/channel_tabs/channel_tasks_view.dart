import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/theme/buzz_icons.dart';
import '../../../shared/theme/theme.dart';
import 'approval_buttons.dart';
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
  final Set<String> _closing = {};
  Timer? _rowsMoved;

  bool get _settling => _rowsMoved?.isActive ?? false;

  @override
  void dispose() {
    _rowsMoved?.cancel();
    super.dispose();
  }

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
    if (_settling) return;
    setState(() => _pending.add(eventId));
    await _run(
      () => widget.onReact(
        eventId,
        decision == OwnerDecision.approve ? approveEmoji : denyEmoji,
      ),
      decision == OwnerDecision.approve
          ? "Couldn't send approval"
          : "Couldn't send denial",
      onSuccess: () {
        _decided[eventId] = decision;
        _holdTaps();
      },
    );
    if (mounted) setState(() => _pending.remove(eventId));
  }

  void _holdTaps() {
    _rowsMoved?.cancel();
    _rowsMoved = Timer(const Duration(milliseconds: 500), () {});
  }

  Future<void> _close(ThreadTask task) async {
    if (_settling) return;
    setState(() => _closing.add(task.rootId));
    await _run(
      () => widget.onDone(task),
      "Couldn't close the task",
      onSuccess: _holdTaps,
    );
    if (mounted) setState(() => _closing.remove(task.rootId));
  }

  Widget _row(ThreadTask task) {
    final ask = task.ask;
    final decision = ask == null
        ? null
        : widget.state.decisions[ask.eventId] ?? _decided[ask.eventId];
    final pending = ask != null && _pending.contains(ask.eventId);
    final textTheme = context.textTheme;
    return InkWell(
      key: Key('task-row-${task.rootId}'),
      onTap: () {
        if (!_settling) widget.onOpenThread(task.rootId);
      },
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          Grid.xs,
          Grid.xxs,
          Grid.half,
          Grid.xxs,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Grid.half),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: Grid.xxs,
                      runSpacing: Grid.quarter,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          task.title,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (decision != null)
                          TaskDecisionChip(decision: decision),
                      ],
                    ),
                    if (ask != null)
                      Padding(
                        padding: const EdgeInsets.only(top: Grid.quarter),
                        child: Text(
                          ask.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (ask != null && decision == null && widget.canSetStatus)
                      Padding(
                        padding: const EdgeInsets.only(top: Grid.xxs),
                        child: DecisionButtons(
                          enabled: !pending,
                          onApprove: () =>
                              _send(ask.eventId, OwnerDecision.approve),
                          onDeny: () => _send(ask.eventId, OwnerDecision.deny),
                          subject: task.title,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (widget.canSetStatus && task.status != TaskStatus.done)
              IconButton(
                tooltip: 'Mark ${task.title} done',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  BuzzIcons.circleCheck,
                  size: 20,
                  color: context.colors.onSurfaceVariant,
                ),
                onPressed: _closing.contains(task.rootId)
                    ? null
                    : () => _close(task),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(String title, int count) => Semantics(
    header: true,
    label: '$title, $count',
    excludeSemantics: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(Grid.xs, Grid.xs, Grid.xs, Grid.half),
      child: Text(
        '$title · $count',
        style: context.textTheme.labelLarge?.copyWith(
          color: context.colors.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );

  Iterable<Widget> _rows(List<ThreadTask> tasks) sync* {
    for (var i = 0; i < tasks.length; i++) {
      if (i > 0) {
        yield const Divider(height: 1, thickness: 0.5, indent: Grid.xs);
      }
      yield _row(tasks[i]);
    }
  }

  List<Widget> _section(String title, List<ThreadTask> tasks) => tasks.isEmpty
      ? const []
      : [_header(title, tasks.length), ..._rows(tasks)];

  Widget _doneHeader(int count) => Semantics(
    key: const Key('tasks-done-toggle'),
    button: true,
    header: true,
    expanded: _showDone,
    label: 'Done, $count',
    hint: _showDone ? 'Hide done tasks' : 'Show done tasks',
    child: InkWell(
      onTap: () => setState(() => _showDone = !_showDone),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Grid.xs, Grid.xs, Grid.xs, Grid.xxs),
        child: Row(
          children: [
            Expanded(
              child: ExcludeSemantics(
                child: Text(
                  'Done · $count',
                  style: context.textTheme.labelLarge?.copyWith(
                    color: context.colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Icon(
              _showDone ? BuzzIcons.chevronDown : BuzzIcons.chevronRight,
              size: 18,
              color: context.colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final groups = widget.state.groups;
    return ListView(
      padding: EdgeInsets.only(
        top: Grid.half,
        bottom: Grid.xs + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        ..._section('Needs you', groups.needsYou),
        ..._section('In progress', groups.inProgress),
        ..._section('Blocked', groups.blocked),
        if (groups.done.isNotEmpty) _doneHeader(groups.done.length),
        if (_showDone) ..._rows(groups.done),
      ],
    );
  }
}
