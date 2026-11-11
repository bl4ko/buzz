import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'olympus_art.dart';
import 'olympus_colors.dart';
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
    final controller = useAnimationController(
      duration: const Duration(milliseconds: 1200),
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

  static const _ink = [
    (0.0, 0.26),
    (0.06, 1.0),
    (0.25, 1.0),
    (0.5, 0.52),
    (0.75, 0.26),
    (1.0, 0.26),
  ];
  static const _highlight = [(0.0, 0.0), (0.06, 0.9), (0.25, 0.0), (1.0, 0.0)];
  static const _cells = [(0, 0), (1, 0), (1, 1), (0, 1)];
  static final _drawings = {
    12: (
      5.0,
      OlympusArt.polygon(
        '.5,5 .5,.5 4.5,.5 4.5,4.5 2.5,4.5 2.5,2',
        close: false,
      ),
    ),
    16: (
      7.0,
      OlympusArt.polygon(
        '.5,7 .5,.5 6.5,.5 6.5,6.5 2.5,6.5 2.5,2.5 4.5,2.5 4.5,5',
        close: false,
      ),
    ),
    20: (
      9.0,
      OlympusArt.polygon(
        '.5,9 .5,.5 8.5,.5 8.5,8.5 3.5,8.5 3.5,3.5 5.5,3.5 5.5,6',
        close: false,
      ),
    ),
  };

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final grid = size.width == 24
        ? 12
        : _drawings.containsKey(size.width)
        ? size.width.toInt()
        : 16;
    final (tile, path) = _drawings[grid]!;
    final hot = ThemeData.estimateBrightnessForColor(color) == Brightness.light
        ? OlympusColors.goldHot
        : OlympusColors.goldInkHot;
    Paint stroke(Color color, double opacity) => Paint()
      ..color = color.withValues(alpha: color.a * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.scale(size.width / grid);
    for (final (index, (column, row)) in _cells.indexed) {
      final at = (progress.value - index / 4) % 1;
      canvas
        ..save()
        ..translate(
          column * (grid - tile) + tile / 2,
          row * (grid - tile) + tile / 2,
        )
        ..rotate(index * pi / 2)
        ..translate(-tile / 2, -tile / 2)
        ..drawPath(
          path,
          stroke(
            color,
            reduced
                ? 0.4 + 0.6 * Curves.easeInOut.transform(progress.value)
                : OlympusMotion.frames(at, _ink),
          ),
        );
      if (!reduced) {
        canvas.drawPath(
          path,
          stroke(hot, OlympusMotion.frames(at, _highlight)),
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(OlympusInlinePainter oldDelegate) =>
      progress != oldDelegate.progress ||
      color != oldDelegate.color ||
      reduced != oldDelegate.reduced;
}
