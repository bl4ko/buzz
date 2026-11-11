import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../theme/theme.dart';
import 'olympus_art.dart';
import 'olympus_key_loader.dart';
import 'use_olympus_reduced_motion.dart';

class OlympusPullKey extends HookWidget {
  const OlympusPullKey({
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
    final controller = useAnimationController(initialValue: 1);
    useEffect(() {
      if (loading && !still) {
        controller
          ..duration = Duration(milliseconds: reduced ? 1600 : 1200)
          ..value = 0
          ..repeat(reverse: reduced);
      } else {
        controller
          ..stop()
          ..value = 1;
      }
      return null;
    }, [controller, loading, reduced, still]);
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

  static const _flash = [(0.0, 0.0), (95.0, 1.0), (380.0, 0.0)];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final flash = OlympusMotion.frames(
      (progress.lastElapsedDuration?.inMicroseconds ?? 0) / 1000,
      _flash,
      Curves.easeOut,
    );
    double at(int index) => (progress.value - index / 8) % 1;
    OlympusKeyPainter.paintTiles(
      canvas,
      size,
      light,
      (index) => !loading
          ? (charge * 8.4 - index).clamp(0.12, 1.0)
          : reduced
          ? OlympusKeyPainter.pulse(progress.value)
          : OlympusMotion.frames(at(index), OlympusKeyPainter.tileFrames),
      !loading || reduced
          ? null
          : (index) => max(
              flash,
              OlympusMotion.frames(at(index), OlympusKeyPainter.glowFrames),
            ),
    );
  }

  @override
  bool shouldRepaint(OlympusPullPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      charge != oldDelegate.charge ||
      loading != oldDelegate.loading ||
      light != oldDelegate.light ||
      reduced != oldDelegate.reduced;
}
