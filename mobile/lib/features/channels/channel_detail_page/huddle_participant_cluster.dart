part of '../channel_detail_page.dart';

const _huddleClusterVisibleParticipantCount = 10;
const _huddleParticipantPresenceScale = 0.72;
const _huddleGridSpacing = Grid.xxs;
const _huddleGridMinFrameSize = 56.0;

class _HuddleParticipantGrid extends StatelessWidget {
  const _HuddleParticipantGrid({
    required this.localPubkey,
    required this.remotePubkeys,
    required this.profiles,
    required this.fallbackLabels,
    required this.contextualLabels,
    required this.activeSpeakerPubkeys,
    required this.speakerLevels,
    required this.workingAgentPubkeys,
    required this.entryDuration,
    required this.onParticipantTap,
    required this.onOverflowTap,
  });

  final String localPubkey;
  final List<String> remotePubkeys;
  final Map<String, UserProfile> profiles;
  final Map<String, String> fallbackLabels;
  final Map<String, String> contextualLabels;
  final Set<String> activeSpeakerPubkeys;
  final Map<String, double> speakerLevels;
  final Set<String> workingAgentPubkeys;
  final Duration entryDuration;
  final ValueChanged<String> onParticipantTap;
  final VoidCallback onOverflowTap;

  @override
  Widget build(BuildContext context) {
    final visibleRemote = remotePubkeys
        .take(_huddleClusterVisibleParticipantCount)
        .toList(growable: false);
    final overflowCount =
        remotePubkeys.length - _huddleClusterVisibleParticipantCount;
    final pubkeys = [localPubkey, ...visibleRemote];
    final tileCount = pubkeys.length + (overflowCount > 0 ? 1 : 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final frameSize = _huddleGridFrameSize(
          count: tileCount,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
        );
        return Wrap(
          key: const ValueKey('huddle-participant-grid'),
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.start,
          spacing: _huddleGridSpacing,
          runSpacing: _huddleGridSpacing,
          children: [
            for (final pubkey in pubkeys)
              _HuddleGridTile(
                key: ValueKey('huddle-participant-entry-$pubkey'),
                pubkey: pubkey,
                profile: pubkey.isEmpty ? null : profiles[pubkey],
                fallbackLabel: fallbackLabels[pubkey],
                contextualLabel: contextualLabels[pubkey],
                isSelf: pubkey == localPubkey,
                active: activeSpeakerPubkeys.contains(pubkey),
                speakerLevel: speakerLevels[pubkey] ?? 0,
                preparingResponse: workingAgentPubkeys.contains(pubkey),
                frameSize: frameSize,
                entryDuration: entryDuration,
                onTap: pubkey == localPubkey
                    ? null
                    : () {
                        unawaited(HapticFeedback.selectionClick());
                        onParticipantTap(pubkey);
                      },
              ),
            if (overflowCount > 0)
              SizedBox(
                width: frameSize,
                height: frameSize + _huddleParticipantLabelSpace,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _HuddleParticipantOverflow(
                    count: overflowCount,
                    size: frameSize * 0.8,
                    entryDuration: entryDuration,
                    onTap: onOverflowTap,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

double _huddleGridFrameSize({
  required int count,
  required double width,
  required double height,
}) {
  if (count <= 0 || !width.isFinite || !height.isFinite) {
    return _huddleAvatarFrameSize;
  }
  var best = _huddleGridMinFrameSize;
  for (var columns = 1; columns <= count; columns++) {
    final rows = (count / columns).ceil();
    final byWidth = (width - _huddleGridSpacing * (columns - 1)) / columns;
    final byHeight =
        (height - _huddleGridSpacing * (rows - 1)) / rows -
        _huddleParticipantLabelSpace;
    best = max(best, min(_huddleAvatarFrameSize, min(byWidth, byHeight)));
  }
  return best;
}

class _HuddleGridTile extends StatelessWidget {
  const _HuddleGridTile({
    super.key,
    required this.pubkey,
    required this.profile,
    required this.fallbackLabel,
    required this.contextualLabel,
    required this.isSelf,
    required this.active,
    required this.speakerLevel,
    required this.preparingResponse,
    required this.frameSize,
    required this.entryDuration,
    required this.onTap,
  });

  final String pubkey;
  final UserProfile? profile;
  final String? fallbackLabel;
  final String? contextualLabel;
  final bool isSelf;
  final bool active;
  final double speakerLevel;
  final bool preparingResponse;
  final double frameSize;
  final Duration entryDuration;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('huddle-participant-entry-motion-$pubkey'),
      duration: entryDuration,
      curve: Curves.easeOutBack,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0, 1),
        child: Transform.scale(
          key: ValueKey('huddle-participant-entry-scale-$pubkey'),
          scale:
              _huddleParticipantPresenceScale +
              value * (1 - _huddleParticipantPresenceScale),
          child: child,
        ),
      ),
      child: _HuddleCallAvatar(
        pubkey: pubkey,
        profile: profile,
        fallbackLabel: fallbackLabel,
        contextualLabel: contextualLabel,
        active: active,
        speakerLevel: speakerLevel,
        preparingResponse: preparingResponse,
        isSelf: isSelf,
        frameSize: frameSize,
        onTap: onTap,
      ),
    );
  }
}

class _HuddleParticipantOverflow extends StatelessWidget {
  const _HuddleParticipantOverflow({
    required this.count,
    required this.size,
    required this.entryDuration,
    required this.onTap,
  });

  final int count;
  final double size;
  final Duration entryDuration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        duration: entryDuration,
        curve: Curves.easeOutBack,
        tween: Tween(begin: 0, end: 1),
        builder: (context, value, child) => Opacity(
          opacity: value.clamp(0, 1),
          child: Transform.scale(scale: 0.95 + value * 0.05, child: child),
        ),
        child: Semantics(
          label: '$count more participants',
          hint: 'Tap to show participant list',
          button: true,
          onTap: onTap,
          child: ExcludeSemantics(
            child: GestureDetector(
              key: const ValueKey('huddle-participant-overflow'),
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: onTap,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.surfaceContainerHighest,
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: entryDuration,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: Text(
                      '+$count',
                      key: ValueKey('huddle-participant-overflow-count-$count'),
                      style: context.textTheme.titleMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
