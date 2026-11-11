import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'olympus_art.dart';
import 'use_olympus_reduced_motion.dart';

class OlympusInlineSpinner extends HookWidget {
  const OlympusInlineSpinner({
    super.key,
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final reduced = useOlympusReducedMotion(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final controller = useAnimationController(initialValue: 1);
    useEffect(() {
      if (still) {
        controller
          ..stop()
          ..value = 1;
      } else {
        controller
          ..duration = Duration(milliseconds: reduced ? 1200 : 900)
          ..repeat(reverse: reduced);
      }
      return null;
    }, [controller, reduced, still]);
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: OlympusInlinePainter(
          progress: controller,
          color: color,
          reduced: reduced,
        ),
      ),
    );
  }
}

class OlympusInlinePainter extends CustomPainter {
  OlympusInlinePainter({
    required this.progress,
    required this.color,
    required this.reduced,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;
  final bool reduced;

  static const _pulse = [(18.0, 0.72), (55.0, 0.0)];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    OlympusArt.fit(canvas, OlympusArt.inlineView, size);
    for (final (index, segment) in OlympusArt.boltSegments.indexed) {
      final opacity = reduced
          ? 0.4 + 0.6 * Curves.easeInOut.transform(progress.value)
          : 0.28 +
                OlympusMotion.keys(
                  (progress.value - index * 0.13 / 0.9) % 1 * 100,
                  _pulse,
                );
      canvas.drawPath(
        segment,
        Paint()..color = color.withValues(alpha: color.a * opacity),
      );
    }
  }

  @override
  bool shouldRepaint(OlympusInlinePainter oldDelegate) =>
      progress != oldDelegate.progress ||
      color != oldDelegate.color ||
      reduced != oldDelegate.reduced;
}
