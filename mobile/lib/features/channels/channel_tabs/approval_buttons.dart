import 'package:flutter/material.dart';

import '../../../shared/theme/theme.dart';
import '../timeline_message.dart';
import 'thread_status.dart';

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
  String? _decision;
  bool _pending = false;

  @override
  void didUpdateWidget(ApprovalButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.askEventId != widget.askEventId) _decision = null;
  }

  Future<void> _send(String emoji) async {
    setState(() => _pending = true);
    try {
      await widget.onReact(emoji);
      if (mounted) {
        setState(
          () => _decision = emoji == approveEmoji ? 'Approved' : 'Denied',
        );
      }
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
    final style = Theme.of(context).textTheme.bodySmall;
    if (mine(approveEmoji) || mine(denyEmoji)) {
      return Text(
        mine(approveEmoji) ? 'You approved' : 'You denied',
        style: style,
      );
    }
    if (_decision != null) return Text(_decision!, style: style);
    return Wrap(
      spacing: Grid.xs,
      children: [
        OutlinedButton(
          onPressed: _pending ? null : () => _send(approveEmoji),
          child: const Text('✅ Approve'),
        ),
        OutlinedButton(
          onPressed: _pending ? null : () => _send(denyEmoji),
          child: const Text('❌ Deny'),
        ),
      ],
    );
  }
}
