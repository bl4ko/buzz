import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../shared/theme/theme.dart';

const _landingHighlightDelay = Duration(milliseconds: 50);
const _landingHighlightTransitionDuration = Duration(milliseconds: 300);
const _landingHighlightOpacity = 0.12;

String? useLandingHighlightTarget(
  BuildContext context,
  String? messageId, {
  required Duration duration,
}) {
  final routeAnimation = ModalRoute.of(context)?.animation;
  final reducedMotion = MediaQuery.disableAnimationsOf(context);
  final highlightedMessageId = useState<String?>(null);
  useEffect(() {
    if (messageId == null) return null;
    var disposed = false;
    Timer? revealTimer;
    Timer? dismissTimer;

    void revealHighlight() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (disposed) return;
        revealTimer = Timer(_landingHighlightDelay, () {
          if (disposed) return;
          highlightedMessageId.value = messageId;
          dismissTimer = Timer(
            duration +
                (reducedMotion
                    ? Duration.zero
                    : _landingHighlightTransitionDuration),
            () {
              if (!disposed) highlightedMessageId.value = null;
            },
          );
        });
      });
    }

    void handleRouteStatus(AnimationStatus status) {
      if (status != AnimationStatus.completed) return;
      routeAnimation?.removeStatusListener(handleRouteStatus);
      revealHighlight();
    }

    if (routeAnimation == null ||
        routeAnimation.status == AnimationStatus.completed) {
      revealHighlight();
    } else {
      routeAnimation.addStatusListener(handleRouteStatus);
    }

    return () {
      disposed = true;
      routeAnimation?.removeStatusListener(handleRouteStatus);
      revealTimer?.cancel();
      dismissTimer?.cancel();
    };
  }, [messageId, reducedMotion, routeAnimation]);
  return highlightedMessageId.value;
}

Color useLandingHighlightColor(
  BuildContext context, {
  required bool isHighlighted,
}) {
  final reducedMotion = MediaQuery.disableAnimationsOf(context);
  final highlightController = useAnimationController(
    duration: _landingHighlightTransitionDuration,
  );
  final highlightProgress = useAnimation(highlightController);
  useEffect(() {
    if (reducedMotion) {
      highlightController.value = isHighlighted ? 1 : 0;
    } else {
      unawaited(
        highlightController.animateTo(
          isHighlighted ? 1 : 0,
          duration: _landingHighlightTransitionDuration,
          curve: Curves.easeOutCubic,
        ),
      );
    }
    return null;
  }, [highlightController, isHighlighted, reducedMotion]);
  return highlightProgress == 0
      ? Colors.transparent
      : context.colors.primary.withValues(
          alpha: _landingHighlightOpacity * highlightProgress,
        );
}
