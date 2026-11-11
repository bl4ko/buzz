import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'olympus_art.dart';
import 'olympus_colors.dart';
import 'use_olympus_reduced_motion.dart';

class OlympusBoltSpinner extends HookWidget {
  const OlympusBoltSpinner({
    super.key,
    required this.size,
    required this.light,
  });

  final double size;
  final bool light;

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
          ..duration = Duration(milliseconds: reduced ? 1600 : 1400)
          ..repeat(reverse: reduced);
      }
      return null;
    }, [controller, reduced, still]);
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: OlympusBoltPainter(
          progress: controller,
          light: light,
          reduced: reduced,
        ),
      ),
    );
  }
}

class OlympusBoltPainter extends CustomPainter {
  OlympusBoltPainter({
    required this.progress,
    required this.light,
    required this.reduced,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final bool light;
  final bool reduced;

  static const _comet = [(110.0, 0.22), (66.0, 0.5), (26.0, 1.0)];
  static const _punch = [(70.0, 0.0), (76.0, 0.1), (90.0, 0.0)];
  static const _glow = [(68.0, 0.0), (76.0, 0.55), (100.0, 0.0)];
  static const _flash = [(69.0, 0.0), (75.0, 1.0), (90.0, 0.0)];

  static Paint ring(bool light, double opacity) => Paint()
    ..shader = light ? OlympusArt.ringGoldLight : OlympusArt.ringGold
    ..color = OlympusColors.white.withValues(alpha: opacity)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 56;

  static Paint track(bool light, double opacity) => Paint()
    ..color = (light ? OlympusColors.lightGoldDeep : OlympusColors.gold)
        .withValues(alpha: opacity)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 56;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final at = progress.value * 100;
    final pulse = reduced
        ? 0.45 + 0.55 * Curves.easeInOut.transform(progress.value)
        : 1.0;
    OlympusArt.fit(canvas, OlympusArt.loaderView, size);
    canvas.drawCircle(
      OlympusArt.center,
      OlympusArt.ringRadius,
      track(light, 0.22),
    );
    if (!reduced) {
      canvas
        ..save()
        ..translate(OlympusArt.center.dx, OlympusArt.center.dy)
        ..rotate(2 * pi * progress.value)
        ..translate(-OlympusArt.center.dx, -OlympusArt.center.dy);
      for (final (degrees, opacity) in _comet) {
        canvas.drawArc(
          Rect.fromCircle(
            center: OlympusArt.center,
            radius: OlympusArt.ringRadius,
          ),
          -degrees * pi / 180,
          degrees * pi / 180,
          false,
          ring(light, opacity)
            ..strokeCap = opacity == 1 ? StrokeCap.round : StrokeCap.butt,
        );
      }
      canvas.restore();
    }
    OlympusArt.loaderBolt(canvas);
    OlympusArt.scaleAbout(
      canvas,
      OlympusArt.boltCenter,
      reduced ? 1 : 1 + OlympusMotion.keys(at, _punch),
    );
    if (!light) {
      OlympusArt.glow(
        canvas,
        OlympusArt.boltGlow,
        OlympusColors.boltGlow,
        reduced ? 0.45 * pulse : 0.45 + OlympusMotion.keys(at, _glow),
      );
    }
    OlympusArt.paintBolt(canvas, light: light, opacity: pulse);
    final flash = reduced ? 0.0 : OlympusMotion.keys(at, _flash);
    if (flash > 0) {
      canvas.drawPath(
        OlympusArt.bolt,
        Paint()
          ..color = (light ? const Color(0xFFFFF6C4) : OlympusColors.white)
              .withValues(alpha: flash * (light ? 0.6 : 0.95)),
      );
    }
  }

  @override
  bool shouldRepaint(OlympusBoltPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      light != oldDelegate.light ||
      reduced != oldDelegate.reduced;
}
