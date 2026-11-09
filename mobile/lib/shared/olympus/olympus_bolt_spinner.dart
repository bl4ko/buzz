import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'olympus_art.dart';
import 'use_olympus_reduced_motion.dart';

class OlympusBoltSpinner extends HookWidget {
  const OlympusBoltSpinner({
    super.key,
    required this.size,
    required this.color,
    this.startCharged = false,
  });

  final double size;
  final Color color;
  final bool startCharged;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = useOlympusReducedMotion(context);
    final controller = useAnimationController(
      duration: const Duration(milliseconds: 1400),
      initialValue: startCharged ? 0.7 : 0,
    );
    useEffect(() {
      if (reducedMotion) {
        controller
          ..stop()
          ..value = 1;
      } else {
        controller.repeat();
      }
      return null;
    }, [controller, reducedMotion]);
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: OlympusBoltPainter(progress: controller, color: color),
      ),
    );
  }
}

class OlympusBoltPainter extends CustomPainter {
  OlympusBoltPainter({required this.progress, required this.color})
    : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const bounds = OlympusArt.boltBounds;
    final scale = size.height / bounds.height;
    final origin = Offset(
      size.width / 2 - bounds.center.dx * scale,
      -bounds.top * scale,
    );
    final bolt = OlympusArt.polygon([
      for (final point in OlympusArt.bolt) origin + point * scale,
    ]);
    final fill = OlympusMotion.charge(progress.value);
    if (fill > 0) {
      canvas
        ..save()
        ..clipPath(bolt)
        ..drawRect(
          Rect.fromLTRB(0, size.height * (1 - fill), size.width, size.height),
          Paint()..color = color,
        )
        ..restore();
    }
    canvas.drawPath(
      bolt,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = max(1.2, size.height * 0.035),
    );
  }

  @override
  bool shouldRepaint(OlympusBoltPainter oldDelegate) =>
      progress != oldDelegate.progress || color != oldDelegate.color;
}
