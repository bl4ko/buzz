import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'olympus_art.dart';
import 'use_olympus_reduced_motion.dart';

class OlympusCloudSpinner extends HookWidget {
  const OlympusCloudSpinner({
    super.key,
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = useOlympusReducedMotion(context);
    final controller = useAnimationController(
      duration: const Duration(milliseconds: 1200),
    );
    useEffect(() {
      if (reducedMotion) {
        controller
          ..stop()
          ..value = 0;
      } else {
        controller.repeat();
      }
      return null;
    }, [controller, reducedMotion]);
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: OlympusCloudPainter(
          progress: controller,
          color: color,
          still: reducedMotion,
        ),
      ),
    );
  }
}

class OlympusCloudPainter extends CustomPainter {
  OlympusCloudPainter({
    required this.progress,
    required this.color,
    this.still = false,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;
  final bool still;

  static const _stillOpacity = [1.0, 0.6, 0.3];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final radius = size.width * 0.125;
    final center = size.center(Offset.zero);
    for (var puff = 0; puff < 3; puff++) {
      final opacity = still
          ? _stillOpacity[puff]
          : OlympusMotion.pulse(progress.value - puff / 6);
      canvas.drawCircle(
        center + Offset((puff - 1) * size.width * 0.36, 0),
        radius,
        Paint()..color = color.withValues(alpha: color.a * opacity),
      );
    }
  }

  @override
  bool shouldRepaint(OlympusCloudPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      color != oldDelegate.color ||
      still != oldDelegate.still;
}
