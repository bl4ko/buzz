import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'olympus_art.dart';
import 'olympus_colors.dart';
import 'use_olympus_reduced_motion.dart';

class OlympusKeyLoader extends HookWidget {
  const OlympusKeyLoader({super.key, required this.size, required this.light});

  final double size;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final reduced = useOlympusReducedMotion(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final controller = useAnimationController(
      duration: const Duration(milliseconds: 1600),
      initialValue: 1,
    );
    useEffect(() {
      if (still) {
        controller
          ..stop()
          ..value = 1;
      } else {
        controller.repeat(reverse: reduced);
      }
      return null;
    }, [controller, reduced, still]);
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: OlympusKeyPainter(
          progress: controller,
          light: light,
          reduced: reduced,
        ),
      ),
    );
  }
}

class OlympusKeyPainter extends CustomPainter {
  OlympusKeyPainter({
    required this.progress,
    required this.light,
    required this.reduced,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final bool light;
  final bool reduced;

  static const tileFrames = [
    (0.0, 0.2),
    (0.04, 1.0),
    (0.125, 1.0),
    (0.25, 0.6),
    (0.375, 0.34),
    (0.5, 0.2),
    (1.0, 0.2),
  ];
  static const glowFrames = [
    (0.0, 0.0),
    (0.04, 0.85),
    (0.125, 0.5),
    (0.25, 0.0),
    (1.0, 0.0),
  ];
  static const _cells = [
    (0, 0, 0),
    (1, 0, 0),
    (2, 0, 1),
    (2, 1, 1),
    (2, 2, 2),
    (1, 2, 2),
    (0, 2, 3),
    (0, 1, 3),
  ];
  static final _tile = OlympusArt.polygon(
    '2,14 2,2 14,2 14,14 6,14 6,6 10,6 10,10',
    close: false,
  );
  static final _glow = OlympusArt.raster(
    const Rect.fromLTRB(-4, -4, 20, 20),
    8,
    (canvas) => canvas.drawPath(
      _tile,
      _stroke(OlympusColors.white, 3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.3),
    ),
  );

  static Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.square;

  static double pulse(double value) =>
      0.45 + 0.55 * Curves.easeInOut.transform(value);

  static void paintTiles(
    Canvas canvas,
    Size size,
    bool light,
    double Function(int index) tile, [
    double Function(int index)? glow,
  ]) {
    final color = light ? OlympusColors.goldInk : OlympusColors.gold;
    canvas.scale(size.width / 48);
    for (final (index, (column, row, turns)) in _cells.indexed) {
      canvas
        ..save()
        ..translate(column * 16 + 8, row * 16 + 8)
        ..rotate(turns * pi / 2)
        ..translate(-8, -8);
      if (glow != null) {
        OlympusArt.sprite(
          canvas,
          _glow,
          tint: light ? OlympusColors.goldInkHot : OlympusColors.goldHot,
          opacity: glow(index),
        );
      }
      canvas
        ..drawPath(_tile, _stroke(color.withValues(alpha: tile(index)), 2))
        ..restore();
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    double at(int index) => (progress.value - index / 8) % 1;
    paintTiles(
      canvas,
      size,
      light,
      (index) => reduced
          ? pulse(progress.value)
          : OlympusMotion.frames(at(index), tileFrames),
      reduced ? null : (index) => OlympusMotion.frames(at(index), glowFrames),
    );
  }

  @override
  bool shouldRepaint(OlympusKeyPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      light != oldDelegate.light ||
      reduced != oldDelegate.reduced;
}
