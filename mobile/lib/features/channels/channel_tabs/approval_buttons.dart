import 'package:flutter/material.dart';

import '../../../shared/theme/theme.dart';
import '../timeline_message.dart';
import 'thread_status.dart';

class ApprovalButtons extends StatelessWidget {
  const ApprovalButtons({
    super.key,
    required this.reactions,
    required this.onReact,
  });

  final List<TimelineReaction> reactions;
  final Future<void> Function(String emoji) onReact;

  @override
  Widget build(BuildContext context) {
    bool mine(String emoji) =>
        reactions.any((r) => r.emoji == emoji && r.reactedByCurrentUser);
    if (mine(approveEmoji) || mine(denyEmoji)) {
      return Text(
        mine(approveEmoji) ? 'You approved' : 'You denied',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Wrap(
      spacing: Grid.xs,
      children: [
        OutlinedButton(
          onPressed: () => onReact(approveEmoji),
          child: const Text('✅ Approve'),
        ),
        OutlinedButton(
          onPressed: () => onReact(denyEmoji),
          child: const Text('❌ Deny'),
        ),
      ],
    );
  }
}
