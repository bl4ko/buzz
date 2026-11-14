import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/profile/user_cache_provider.dart';
import '../../shared/theme/buzz_icons.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/avatar_image.dart';
import 'olympus_provider.dart';
import 'olympus_state.dart';

/// The error color, lightened until text on the page surface reads well.
/// Some themes (Storm) use a muted git deletion red for `error`.
Color olympusDanger(BuildContext context) {
  final error = context.colors.error;
  final surface = context.colors.surface.computeLuminance();
  double contrast(Color color) {
    final value = color.computeLuminance();
    return (math.max(value, surface) + 0.05) /
        (math.min(value, surface) + 0.05);
  }

  final toward = context.theme.brightness == Brightness.dark
      ? Colors.white
      : Colors.black;
  var color = error;
  for (var step = 1; step <= 10 && contrast(color) < 4.5; step++) {
    color = Color.lerp(error, toward, step / 10)!;
  }
  return color;
}

enum OlympusDisplayState { online, working, suspended, starting }

OlympusDisplayState olympusDisplayState(OlympusAgent agent, bool working) =>
    switch (agent.phase) {
      OlympusPhase.suspended => OlympusDisplayState.suspended,
      _ when working => OlympusDisplayState.working,
      OlympusPhase.online => OlympusDisplayState.online,
      _ => OlympusDisplayState.starting,
    };

String olympusAgentLabel(WidgetRef ref, OlympusAgent agent) {
  final key = agent.publicKey;
  final profile = key == null ? null : ref.watch(userCacheProvider)[key];
  final name = profile?.displayName?.trim();
  return name != null && name.isNotEmpty ? name : agent.label;
}

String formatOlympusAgo(DateTime time, [DateTime? now]) {
  final span = (now ?? DateTime.now()).difference(time);
  if (span.inSeconds < 60) return 'just now';
  if (span.inMinutes < 60) return '${span.inMinutes} min ago';
  if (span.inHours < 24) return '${span.inHours} h ago';
  return '${span.inDays} d ago';
}

class OlympusAgentAvatar extends ConsumerWidget {
  const OlympusAgentAvatar({required this.agent, this.size = 36, super.key});
  final OlympusAgent agent;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = agent.publicKey;
    final profile = ref.watch(
      userCacheProvider.select(
        (profiles) => key == null ? null : profiles[key],
      ),
    );
    if (key != null && profile == null) {
      ref.read(userCacheProvider.notifier).preload([key]);
    }
    final label = olympusAgentLabel(ref, agent);
    return AvatarImage(
      imageUrl: profile?.avatarUrl ?? agent.spec.picture,
      radius: size / 2,
      isAgent: true,
      backgroundColor: context.controlSurface,
      fallback: Text(
        label.isEmpty ? '?' : label.characters.first.toUpperCase(),
        style: context.textTheme.labelLarge?.copyWith(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w600,
          color: context.colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class OlympusStateLabel extends StatelessWidget {
  const OlympusStateLabel({required this.state, super.key});
  final OlympusDisplayState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      OlympusDisplayState.online => ('Online', context.appColors.success),
      OlympusDisplayState.working => ('Working', context.colors.primary),
      OlympusDisplayState.suspended => ('Suspended', context.colors.outline),
      OlympusDisplayState.starting => ('Starting', context.appColors.warning),
    };
    return Semantics(
      label: 'State $label',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: state == OlympusDisplayState.suspended
                  ? Colors.transparent
                  : color,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 1.5),
            ),
          ),
          const SizedBox(width: Grid.half + 1),
          Text(
            label,
            style: context.textTheme.labelMedium?.copyWith(
              color: state == OlympusDisplayState.working
                  ? color
                  : context.colors.onSurfaceVariant,
              fontWeight: state == OlympusDisplayState.working
                  ? FontWeight.w600
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class OlympusMasterMark extends StatelessWidget {
  const OlympusMasterMark({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: context.colors.primary.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(Radii.full),
    ),
    child: Text(
      'Master',
      style: context.textTheme.labelSmall?.copyWith(
        color: context.colors.primary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    ),
  );
}

class OlympusCountBadge extends StatelessWidget {
  const OlympusCountBadge({required this.count, super.key});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 20),
    height: 20,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.colors.error,
      borderRadius: BorderRadius.circular(Radii.full),
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      style: context.textTheme.labelSmall?.copyWith(
        color: context.colors.onError,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
    ),
  );
}

class OlympusGitLock extends StatelessWidget {
  const OlympusGitLock({this.label = 'Set in git', super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(BuzzIcons.lock, size: 14, color: context.tertiaryTextColor),
        const SizedBox(width: Grid.quarter),
        Text(
          'git',
          style: context.textTheme.labelSmall?.copyWith(
            color: context.tertiaryTextColor,
          ),
        ),
      ],
    ),
  );
}

/// The answer to the last change request for one target.
class OlympusRequestLine extends StatelessWidget {
  const OlympusRequestLine({required this.state, this.onDismiss, super.key});
  final OlympusRequestState? state;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final request = state;
    if (request == null) return const SizedBox.shrink();
    final (icon, color, text) = switch (request.phase) {
      OlympusRequestPhase.pending => (
        null,
        context.colors.onSurfaceVariant,
        'Sending ${request.action}…',
      ),
      OlympusRequestPhase.accepted => (
        BuzzIcons.circleCheck,
        context.appColors.success,
        'Done: ${request.reason ?? request.action}',
      ),
      OlympusRequestPhase.refused => (
        BuzzIcons.circleX,
        olympusDanger(context),
        'Refused: ${request.reason ?? 'no reason'}',
      ),
      OlympusRequestPhase.failed => (
        BuzzIcons.triangleAlert,
        olympusDanger(context),
        request.reason ?? 'The request failed.',
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon == null)
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, size: 16, color: color),
          const SizedBox(width: Grid.xxs),
          Expanded(
            child: Text(
              text,
              style: context.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
          if (onDismiss != null && request.phase != OlympusRequestPhase.pending)
            InkWell(
              onTap: onDismiss,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  BuzzIcons.x,
                  size: 14,
                  semanticLabel: 'Dismiss',
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A rounded, tinted pill button for the main actions of a page or card.
class OlympusPillButton extends StatelessWidget {
  const OlympusPillButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.prominent = false,
    this.destructive = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool prominent;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final accent = destructive ? context.colors.error : context.colors.primary;
    final style = prominent
        ? FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: destructive
                ? context.colors.onError
                : context.colors.onPrimary,
          )
        : FilledButton.styleFrom(
            backgroundColor: accent.withValues(alpha: 0.12),
            foregroundColor: accent,
          );
    return FilledButton.icon(
      onPressed: onPressed,
      style: style.copyWith(
        minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: Grid.xs),
        ),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        textStyle: WidgetStatePropertyAll(
          context.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}
