part of '../channel_detail_page.dart';

class _HuddleCallParticipants extends StatelessWidget {
  const _HuddleCallParticipants({
    required this.connected,
    required this.error,
    required this.profiles,
    required this.fallbackLabels,
    required this.contextualLabels,
    required this.remotePubkeys,
    required this.localPubkey,
    required this.activeSpeakerPubkeys,
    required this.speakerLevels,
    required this.workingAgentPubkeys,
    required this.retryTooltip,
    required this.retryIcon,
    required this.onRetry,
    required this.onParticipantTap,
    required this.onOverflowTap,
  });

  final bool connected;
  final String? error;
  final Map<String, UserProfile> profiles;
  final Map<String, String> fallbackLabels;

  /// Huddle-scoped identity labels, keyed by lowercase pubkey.
  final Map<String, String> contextualLabels;
  final List<String> remotePubkeys;
  final String? localPubkey;
  final Set<String> activeSpeakerPubkeys;
  final Map<String, double> speakerLevels;
  final Set<String> workingAgentPubkeys;
  final String retryTooltip;
  final IconData retryIcon;
  final VoidCallback onRetry;
  final ValueChanged<String> onParticipantTap;
  final VoidCallback onOverflowTap;

  @override
  Widget build(BuildContext context) {
    if (error case final message?) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                BuzzIcons.triangleAlert,
                size: 32,
                color: context.colors.error,
              ),
              const SizedBox(height: Grid.xxs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: context.colors.error,
                ),
              ),
              const SizedBox(height: Grid.xs),
              IconButton.filledTonal(
                key: const ValueKey('huddle-retry'),
                tooltip: retryTooltip,
                onPressed: onRetry,
                icon: Icon(retryIcon),
              ),
            ],
          ),
        ),
      );
    }

    if (!connected) {
      return const Center(child: _HuddleLoadingBee());
    }

    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final entryDuration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 420);

    return Container(
      key: const ValueKey('huddle-participant-stage'),
      alignment: Alignment.center,
      child: _HuddleParticipantGrid(
        localPubkey: localPubkey ?? '',
        remotePubkeys: remotePubkeys,
        profiles: profiles,
        fallbackLabels: fallbackLabels,
        contextualLabels: contextualLabels,
        activeSpeakerPubkeys: activeSpeakerPubkeys,
        speakerLevels: speakerLevels,
        workingAgentPubkeys: workingAgentPubkeys,
        entryDuration: entryDuration,
        onParticipantTap: onParticipantTap,
        onOverflowTap: onOverflowTap,
      ),
    );
  }
}

class _HuddleLoadingBee extends HookWidget {
  const _HuddleLoadingBee();

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final flapController = useAnimationController(
      duration: const Duration(milliseconds: 480),
    );
    final flapProgress = useAnimation(flapController);
    useEffect(() {
      if (reducedMotion) {
        flapController
          ..stop()
          ..reset();
      } else {
        flapController.repeat();
      }
      return null;
    }, [flapController, reducedMotion]);
    final flapAmount = reducedMotion
        ? 0.0
        : 0.5 - (0.5 * cos(flapProgress * 4 * pi));

    return Semantics(
      label: 'Joining Huddle',
      liveRegion: true,
      child: ExcludeSemantics(
        child: FlappingBee(
          key: const ValueKey('huddle-loading-bee'),
          width: 60,
          color: context.colors.primary,
          flapAmount: flapAmount,
        ),
      ),
    );
  }
}
