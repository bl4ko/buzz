import 'dart:math' show min, pi;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../theme/theme.dart';
import 'olympus_art.dart';
import 'olympus_bolt_spinner.dart';
import 'olympus_colors.dart';
import 'use_olympus_reduced_motion.dart';

class OlympusPullBolt extends HookWidget {
  const OlympusPullBolt({
    super.key,
    required this.height,
    required this.charge,
    required this.loading,
  });

  final double height;
  final double charge;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final reduced = useOlympusReducedMotion(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final armed = charge >= 1;
    final controller = useAnimationController(initialValue: 1);
    useEffect(() {
      if (loading && !still) {
        controller
          ..duration = Duration(milliseconds: reduced ? 1200 : 900)
          ..value = 0
          ..repeat(reverse: reduced);
      } else if (armed && !reduced) {
        controller
          ..duration = const Duration(milliseconds: 160)
          ..forward(from: 0);
      } else {
        controller
          ..stop()
          ..value = 1;
      }
      return null;
    }, [controller, loading, armed, reduced, still]);
    return Center(
      child: CustomPaint(
        size: Size.square(height),
        painter: OlympusPullPainter(
          progress: controller,
          charge: charge.clamp(0.0, 1.0),
          loading: loading,
          light: context.colors.brightness == Brightness.light,
          reduced: reduced,
        ),
      ),
    );
  }
}

class OlympusPullPainter extends CustomPainter {
  OlympusPullPainter({
    required this.progress,
    required this.charge,
    required this.loading,
    required this.light,
    required this.reduced,
  }) : super(repaint: progress);

  final AnimationController progress;
  final double charge;
  final bool loading;
  final bool light;
  final bool reduced;

  static const _flash = [(80.0, 1.0), (320.0, 0.0)];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final elapsed = (progress.lastElapsedDuration?.inMicroseconds ?? 0) / 1000;
    final spinning = loading && !reduced;
    final sweep = !loading
        ? charge
        : reduced
        ? 1.0
        : lerpDouble(1, 0.28, min(1, elapsed / 160))!;
    OlympusArt.fit(canvas, OlympusArt.loaderView, size);
    canvas.drawCircle(
      OlympusArt.center,
      OlympusArt.ringRadius,
      OlympusBoltPainter.track(light, 0.2),
    );
    if (sweep > 0) {
      canvas
        ..save()
        ..translate(OlympusArt.center.dx, OlympusArt.center.dy)
        ..rotate((spinning ? 2 * pi * progress.value : 0) - pi / 2)
        ..translate(-OlympusArt.center.dx, -OlympusArt.center.dy)
        ..drawArc(
          Rect.fromCircle(
            center: OlympusArt.center,
            radius: OlympusArt.ringRadius,
          ),
          0,
          2 * pi * sweep,
          false,
          OlympusBoltPainter.ring(light, 1)..strokeCap = StrokeCap.round,
        )
        ..restore();
    }

    OlympusArt.loaderBolt(canvas);
    if (!loading && !reduced) {
      final pop = 1 + 0.18 * (1 - Curves.easeOut.transform(progress.value));
      canvas
        ..translate(OlympusArt.boltCenter.dx, OlympusArt.boltCenter.dy)
        ..rotate(-24 * pi / 180 * (1 - charge))
        ..scale((0.6 + 0.4 * charge) * pop)
        ..translate(-OlympusArt.boltCenter.dx, -OlympusArt.boltCenter.dy);
    }
    OlympusArt.paintBolt(
      canvas,
      light: light,
      opacity: !loading
          ? 0.3 + 0.7 * charge
          : reduced
          ? 0.45 + 0.55 * Curves.easeInOut.transform(progress.value)
          : 1,
    );
    final flash = spinning
        ? OlympusMotion.keys(elapsed, _flash, Curves.easeOut)
        : 0.0;
    if (flash > 0) {
      canvas.drawPath(
        OlympusArt.bolt,
        Paint()
          ..color = (light ? const Color(0xFFFFE9A0) : OlympusColors.white)
              .withValues(alpha: flash),
      );
    }
  }

  @override
  bool shouldRepaint(OlympusPullPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      charge != oldDelegate.charge ||
      loading != oldDelegate.loading ||
      light != oldDelegate.light ||
      reduced != oldDelegate.reduced;
}
