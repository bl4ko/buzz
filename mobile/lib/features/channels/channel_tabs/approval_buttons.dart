import 'package:flutter/material.dart';

import '../../../shared/theme/theme.dart';
import '../timeline_message.dart';
import 'thread_status.dart';

class TaskDecisionChip extends StatelessWidget {
  const TaskDecisionChip({super.key, required this.decision, this.label});

  final OwnerDecision decision;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final color = decision == OwnerDecision.approve
        ? context.appColors.success
        : context.colors.error;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Grid.xxs,
        vertical: Grid.quarter,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(Grid.xxs),
      ),
      child: Text(
        label ?? (decision == OwnerDecision.approve ? 'Approved' : 'Denied'),
        maxLines: 1,
        style: context.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class DecisionButtons extends StatelessWidget {
  const DecisionButtons({
    super.key,
    required this.enabled,
    required this.onApprove,
    required this.onDeny,
  });

  final bool enabled;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    const density = VisualDensity(horizontal: -2, vertical: -2);
    return Wrap(
      spacing: Grid.xxs,
      runSpacing: Grid.half,
      children: [
        FilledButton(
          style: FilledButton.styleFrom(visualDensity: density),
          onPressed: enabled ? onApprove : null,
          child: const Text('Approve'),
        ),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            visualDensity: density,
            foregroundColor: context.colors.error,
          ),
          onPressed: enabled ? onDeny : null,
          child: const Text('Deny'),
        ),
      ],
    );
  }
}

class ApprovalButtons extends StatefulWidget {
  const ApprovalButtons({
    super.key,
    required this.askEventId,
    required this.reactions,
    required this.onReact,
  });

  final String askEventId;
  final List<TimelineReaction> reactions;
  final Future<void> Function(String emoji) onReact;

  @override
  State<ApprovalButtons> createState() => _ApprovalButtonsState();
}

class _ApprovalButtonsState extends State<ApprovalButtons> {
  OwnerDecision? _decision;
  bool _pending = false;

  @override
  void didUpdateWidget(ApprovalButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.askEventId != widget.askEventId) _decision = null;
  }

  Future<void> _send(OwnerDecision decision) async {
    setState(() => _pending = true);
    try {
      await widget.onReact(
        decision == OwnerDecision.approve ? approveEmoji : denyEmoji,
      );
      if (mounted) setState(() => _decision = decision);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text("Couldn't send the decision")),
        );
      }
    }
    if (mounted) setState(() => _pending = false);
  }

  @override
  Widget build(BuildContext context) {
    bool mine(String emoji) =>
        widget.reactions.any((r) => r.emoji == emoji && r.reactedByCurrentUser);
    if (mine(approveEmoji) || mine(denyEmoji)) {
      final approved = mine(approveEmoji);
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TaskDecisionChip(
          decision: approved ? OwnerDecision.approve : OwnerDecision.deny,
          label: approved ? 'You approved' : 'You denied',
        ),
      );
    }
    final decision = _decision;
    if (decision != null) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TaskDecisionChip(decision: decision),
      );
    }
    return DecisionButtons(
      enabled: !_pending,
      onApprove: () => _send(OwnerDecision.approve),
      onDeny: () => _send(OwnerDecision.deny),
    );
  }
}
