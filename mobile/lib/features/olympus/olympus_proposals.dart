import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/theme/buzz_icons.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/confirmation_dialog.dart';
import '../../shared/widgets/frosted_app_bar.dart';
import '../../shared/widgets/frosted_scaffold.dart';
import '../../shared/widgets/ios_native_segmented_control.dart';
import '../../shared/widgets/modal_presentation.dart';
import 'olympus_provider.dart';
import 'olympus_state.dart';
import 'olympus_widgets.dart';

const maxRejectReasonBytes = 1000;

/// Approve (with the high-risk second confirmation) or reject with a reason.
Future<void> decideOlympusProposal(
  BuildContext context,
  WidgetRef ref,
  OlympusProposal proposal, {
  required bool approve,
}) async {
  final target = OlympusChangeTarget(
    operator: proposal.author,
    workspace: proposal.workspace,
  );
  final OlympusChange change;
  if (approve) {
    if (proposal.isHighRisk &&
        !await showDestructiveConfirmation(
          context: context,
          title: 'Approve a high-risk change?',
          message:
              '${proposal.requester} asks to ${proposal.operation} '
              '${proposal.targetKind} ${proposal.targetName} in workspace '
              '${proposal.workspace}. High risk: '
              '${proposal.highRisk.join(', ')}. Hephaestus applies the change '
              'when you approve.',
          confirmLabel: 'Approve',
        )) {
      return;
    }
    change = OlympusChange.approve(proposal, highRisk: proposal.isHighRisk);
  } else {
    final reason = await showOlympusRejectSheet(context, proposal);
    if (reason == null) return;
    change = OlympusChange.reject(proposal, reason: reason);
  }
  unawaited(HapticFeedback.mediumImpact());
  await ref.read(olympusProvider.notifier).submit(proposal.key, target, change);
}

/// Returns the trimmed reason (may be empty), or null when cancelled.
Future<String?> showOlympusRejectSheet(
  BuildContext context,
  OlympusProposal proposal,
) => showBuzzModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  title: 'Reject proposal',
  builder: (_) => _RejectSheet(proposal: proposal),
);

class _RejectSheet extends HookWidget {
  const _RejectSheet({required this.proposal});
  final OlympusProposal proposal;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController();
    useListenable(controller);
    final bytes = utf8.encode(controller.text.trim()).length;
    final tooLong = bytes > maxRejectReasonBytes;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Grid.gutter,
        0,
        Grid.gutter,
        MediaQuery.viewInsetsOf(context).bottom + Grid.xs,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${proposal.title}. The reason goes back to ${proposal.requester}.',
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Grid.xs),
          TextField(
            key: const ValueKey('olympus-reject-reason'),
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Reason (optional)',
              errorText: tooLong ? 'Use 1000 bytes or less.' : null,
              filled: true,
              fillColor: context.colors.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.lg),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: Grid.xs),
          FilledButton(
            key: const ValueKey('olympus-reject-confirm'),
            onPressed: tooLong
                ? null
                : () => Navigator.of(context).pop(controller.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              foregroundColor: context.colors.onError,
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
            ),
            child: const Text('Reject proposal'),
          ),
        ],
      ),
    );
  }
}

String _span(int seconds) {
  if (seconds < 60) return '<1 min';
  if (seconds < 3600) return '${seconds ~/ 60} min';
  if (seconds < 86400) return '${seconds ~/ 3600} h';
  return '${seconds ~/ 86400} d';
}

String _timeLine(OlympusProposal proposal, int now) {
  final age = '${_span(now - proposal.createdAt)} ago';
  return proposal.isOpen(now)
      ? '$age · expires in ${_span(proposal.expiresAt - now)}'
      : age;
}

String _statusLabel(OlympusProposalPhase phase) =>
    '${phase.name[0].toUpperCase()}${phase.name.substring(1)}';

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.phase);
  final OlympusProposalPhase phase;

  @override
  Widget build(BuildContext context) {
    final color = switch (phase) {
      OlympusProposalPhase.pending => context.colors.primary,
      OlympusProposalPhase.applied => context.appColors.success,
      OlympusProposalPhase.rejected ||
      OlympusProposalPhase.refused ||
      OlympusProposalPhase.failed => context.colors.error,
      OlympusProposalPhase.expired => context.colors.outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Radii.full),
      ),
      child: Text(
        _statusLabel(phase),
        style: context.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow(this.diff);
  final OlympusProposalDiff diff;

  @override
  Widget build(BuildContext context) {
    final mono = context.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Courier'],
      fontSize: 12,
    );
    final from = olympusDiffText(diff.from);
    final to = olympusDiffText(diff.to);
    Widget value(String? text, Color color, String marker) => Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Text(
        '$marker ${text ?? 'unset'}',
        maxLines: 6,
        overflow: TextOverflow.ellipsis,
        style: mono?.copyWith(color: color),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: Grid.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            diff.path,
            style: mono?.copyWith(color: context.colors.onSurfaceVariant),
          ),
          value(from, context.colors.error, '−'),
          value(to, context.appColors.success, '+'),
        ],
      ),
    );
  }
}

class OlympusProposalCard extends ConsumerWidget {
  const OlympusProposalCard({
    required this.proposal,
    this.compact = false,
    this.onDetails,
    super.key,
  });

  final OlympusProposal proposal;
  final bool compact;
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = olympusNow();
    final request = ref.watch(
      olympusProvider.select((s) => s.requests[proposal.key]),
    );
    final busy = request?.phase == OlympusRequestPhase.pending;
    final open = proposal.isOpen(now);
    final danger = proposal.isHighRisk && open;
    final diff = compact ? proposal.diff.take(2).toList() : proposal.diff;
    return Container(
      key: ValueKey('olympus-proposal-${proposal.name}'),
      padding: const EdgeInsets.all(Grid.xs),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.container),
        border: Border.all(
          color: danger
              ? context.colors.error.withValues(alpha: 0.6)
              : context.colors.onSurface.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      proposal.title,
                      style: context.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: Grid.quarter),
                    Text(
                      '${proposal.workspace} · ${_timeLine(proposal, now)}',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Grid.xxs),
              _StatusBadge(proposal.statusAt(now)),
            ],
          ),
          if (proposal.isHighRisk) ...[
            const SizedBox(height: Grid.twelve),
            Container(
              key: const ValueKey('olympus-proposal-high-risk'),
              padding: const EdgeInsets.symmetric(
                horizontal: Grid.twelve,
                vertical: Grid.xxs,
              ),
              decoration: BoxDecoration(
                color: context.colors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Radii.lg),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    BuzzIcons.shieldAlert,
                    size: 16,
                    color: context.colors.error,
                  ),
                  const SizedBox(width: Grid.xxs),
                  Expanded(
                    child: Text(
                      'High risk: ${proposal.highRisk.join(', ')}',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Grid.twelve),
          Text(
            proposal.reason,
            maxLines: compact ? 3 : null,
            overflow: compact ? TextOverflow.ellipsis : null,
            style: context.textTheme.bodyMedium,
          ),
          for (final entry in diff) _DiffRow(entry),
          if (compact && proposal.diff.length > diff.length)
            Padding(
              padding: const EdgeInsets.only(top: Grid.xxs),
              child: Text(
                '${proposal.diff.length - diff.length} more changes',
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          if (!compact && proposal.diffTruncated)
            Padding(
              padding: const EdgeInsets.only(top: Grid.xxs),
              child: Text(
                'The diff is too large to show here.',
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: Grid.twelve),
          if (open)
            Wrap(
              spacing: Grid.xxs,
              runSpacing: Grid.xxs,
              children: [
                OlympusPillButton(
                  key: const ValueKey('olympus-proposal-approve'),
                  label: 'Approve',
                  icon: BuzzIcons.check,
                  prominent: true,
                  destructive: proposal.isHighRisk,
                  onPressed: busy
                      ? null
                      : () => decideOlympusProposal(
                          context,
                          ref,
                          proposal,
                          approve: true,
                        ),
                ),
                OlympusPillButton(
                  key: const ValueKey('olympus-proposal-reject'),
                  label: 'Reject',
                  icon: BuzzIcons.x,
                  onPressed: busy
                      ? null
                      : () => decideOlympusProposal(
                          context,
                          ref,
                          proposal,
                          approve: false,
                        ),
                ),
                if (onDetails != null)
                  TextButton(
                    onPressed: onDetails,
                    child: const Text('Details'),
                  ),
              ],
            )
          else if (proposal.resultReason != null || proposal.decidedAt != null)
            Text(
              'Result: ${proposal.resultReason ?? _statusLabel(proposal.statusAt(now))}'
              '${proposal.decidedAt == null ? '' : ' · ${_span(now - proposal.decidedAt!)} ago'}',
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          if (request != null) ...[
            const SizedBox(height: Grid.xxs),
            OlympusRequestLine(
              state: request,
              onDismiss: () =>
                  ref.read(olympusProvider.notifier).clearRequest(proposal.key),
            ),
          ],
        ],
      ),
    );
  }
}

void showOlympusProposalSheet(BuildContext context, OlympusProposal proposal) {
  unawaited(
    showBuzzModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      title: 'Proposal',
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Grid.gutter,
            0,
            Grid.gutter,
            Grid.xs,
          ),
          child: Consumer(
            builder: (_, ref, _) {
              final current = ref.watch(
                olympusProvider.select(
                  (s) => s.proposals
                      .where((p) => p.key == proposal.key)
                      .firstOrNull,
                ),
              );
              return OlympusProposalCard(proposal: current ?? proposal);
            },
          ),
        ),
      ),
    ),
  );
}

/// Open proposals of [requesterKey], and the ones with an answer still shown.
List<OlympusProposal> visibleDmProposals(
  OlympusSnapshot snapshot,
  String requesterKey,
  int now,
) => [
  for (final proposal in snapshot.proposals)
    if (proposal.requesterKey == requesterKey &&
        (proposal.isOpen(now) || snapshot.requests.containsKey(proposal.key)))
      proposal,
];

/// Approval cards above the composer of the requester's DM.
class OlympusDmProposals extends ConsumerWidget {
  const OlympusDmProposals({required this.peer, super.key});
  final String peer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(olympusPendingCountProvider);
    final snapshot = ref.watch(olympusProvider);
    final proposals = visibleDmProposals(snapshot, peer, olympusNow());
    if (proposals.isEmpty) return const SizedBox.shrink();
    final first = proposals.first;
    return Padding(
      key: const ValueKey('olympus-dm-proposals'),
      padding: const EdgeInsets.fromLTRB(Grid.xs, 0, Grid.xs, Grid.xxs),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.4,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OlympusProposalCard(
                proposal: first,
                compact: true,
                onDetails: () => showOlympusProposalSheet(context, first),
              ),
              if (proposals.length > 1)
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const OlympusProposalsPage(),
                    ),
                  ),
                  child: Text('${proposals.length - 1} more proposals'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class OlympusSegments extends StatelessWidget {
  const OlympusSegments({
    required this.items,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final List<String> items;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return IosNativeSegmentedControl(
        items: items,
        selectedIndex: selected,
        onChanged: onChanged,
        height: 36,
      );
    }
    return SegmentedButton<int>(
      showSelectedIcon: false,
      segments: [
        for (final (index, item) in items.indexed)
          ButtonSegment(value: index, label: Text(item)),
      ],
      selected: {selected},
      onSelectionChanged: (value) => onChanged(value.first),
    );
  }
}

class OlympusProposalsPage extends HookConsumerWidget {
  const OlympusProposalsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = useState(0);
    ref.watch(olympusPendingCountProvider);
    final snapshot = ref.watch(olympusProvider);
    final now = olympusNow();
    final proposals = filter.value == 0
        ? snapshot.proposals.where((p) => p.isOpen(now)).toList()
        : snapshot.proposals;
    final topHeight = frostedAppBarHeight(
      context,
      nativeLargeTitle: true,
      bottomHeight: Grid.xxs,
    );
    return FrostedScaffold(
      useUtilitySurfaceTheme: true,
      appBar: const FrostedAppBar(
        nativeTitle: 'Proposals',
        nativeLargeTitle: true,
        title: Text('Proposals'),
        horizontalInset: Grid.gutter,
        bottomHeight: Grid.xxs,
        bottom: SizedBox.expand(),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          Grid.gutter,
          topHeight + Grid.xxs,
          Grid.gutter,
          MediaQuery.paddingOf(context).bottom + Grid.md,
        ),
        children: [
          OlympusSegments(
            items: const ['Open', 'All'],
            selected: filter.value,
            onChanged: (index) => filter.value = index,
          ),
          const SizedBox(height: Grid.xs),
          if (proposals.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Grid.xl),
              child: Text(
                !snapshot.loaded
                    ? 'Loading proposals…'
                    : filter.value == 0
                    ? 'No proposals wait for you.'
                    : 'No proposals in the last 7 days.',
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          for (final proposal in proposals) ...[
            OlympusProposalCard(proposal: proposal),
            const SizedBox(height: Grid.twelve),
          ],
        ],
      ),
    );
  }
}
