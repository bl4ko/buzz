import 'dart:ui';

import 'package:flutter/animation.dart';

import 'olympus_colors.dart';

abstract final class OlympusArt {
  static const mountain = [
    Offset(110, 860),
    Offset(512, 230),
    Offset(914, 860),
  ];
  static const shade = [Offset(512, 230), Offset(914, 860), Offset(600, 860)];
  static const snow = [
    Offset(512, 230),
    Offset(610, 372),
    Offset(566, 350),
    Offset(532, 392),
    Offset(494, 352),
    Offset(452, 382),
    Offset(414, 372),
  ];
  static const bolt = [
    Offset(742, 70),
    Offset(610, 330),
    Offset(690, 330),
    Offset(600, 560),
    Offset(830, 262),
    Offset(740, 262),
    Offset(830, 70),
  ];
  static const boltBounds = Rect.fromLTRB(600, 70, 830, 560);
  static const markViewBox = Rect.fromLTWH(-16, -63, 1056, 1056);

  static Path polygon(List<Offset> points) => Path()..addPolygon(points, true);

  static void paintMountain(Canvas canvas) {
    canvas
      ..drawPath(polygon(mountain), Paint()..color = OlympusColors.mountain)
      ..drawPath(polygon(shade), Paint()..color = OlympusColors.mountainShade)
      ..drawPath(polygon(snow), Paint()..color = OlympusColors.marble);
  }

  static Path cloud(Offset center, double unit) {
    Rect circle(double dx, double dy, double r) => Rect.fromCircle(
      center: center + Offset(dx, dy) * unit,
      radius: r * unit,
    );
    return Path()
      ..addOval(circle(-40, 0, 30))
      ..addOval(circle(0, -16, 40))
      ..addOval(circle(42, 0, 28))
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            center.dx - 70 * unit,
            center.dy - 2 * unit,
            140 * unit,
            30 * unit,
          ),
          Radius.circular(15 * unit),
        ),
      );
  }

  static void paintFrontCloud(Canvas canvas, Offset center, double unit) {
    canvas
      ..drawPath(
        cloud(center, unit),
        Paint()..color = OlympusColors.cloudShadow,
      )
      ..drawPath(
        cloud(center - Offset(0, 8 * unit), unit),
        Paint()..color = OlympusColors.marble,
      );
  }

  static void paintBackCloud(
    Canvas canvas,
    Offset center,
    double unit, {
    double opacity = 0.45,
  }) {
    canvas.drawPath(
      cloud(center, unit),
      Paint()..color = OlympusColors.cloudShadow.withValues(alpha: opacity),
    );
  }
}

abstract final class OlympusMotion {
  static const cycle = Duration(seconds: 2772);
  static const strikePeriod = 6.0;

  static double drift(double seconds, double period) {
    final phase = (seconds % (2 * period)) / period;
    final forward = phase < 1;
    final eased = Curves.easeInOut.transform(forward ? phase : phase - 1);
    return forward ? eased * 2 - 1 : 1 - eased * 2;
  }

  static double _segment(double phase, double from, double to) =>
      ((phase - from) / (to - from)).clamp(0.0, 1.0);

  static ({double opacity, double lift, double scale}) strike(double seconds) {
    final phase = (seconds % strikePeriod) / strikePeriod;
    if (phase < 0.86) return (opacity: 0, lift: 1, scale: 0.96);
    if (phase < 0.88) {
      final t = Curves.easeOut.transform(_segment(phase, 0.86, 0.88));
      return (opacity: t, lift: 1 - t, scale: 0.96 + 0.04 * t);
    }
    final double opacity;
    if (phase < 0.92) {
      opacity = 1 - 0.65 * Curves.easeOut.transform(_segment(phase, .88, .92));
    } else if (phase < 0.94) {
      opacity =
          0.35 + 0.65 * Curves.easeOut.transform(_segment(phase, .92, .94));
    } else {
      opacity = 1;
    }
    return (opacity: opacity, lift: 0, scale: 1);
  }

  static double flash(double seconds) {
    final phase = (seconds % strikePeriod) / strikePeriod;
    if (phase < 0.87 || phase >= 0.96) return 0;
    if (phase < 0.88) return 0.35 * _segment(phase, 0.87, 0.88);
    if (phase < 0.90) return 0.35 * (1 - _segment(phase, 0.88, 0.90));
    if (phase < 0.93) return 0.18 * _segment(phase, 0.90, 0.93);
    return 0.18 * (1 - _segment(phase, 0.93, 0.96));
  }

  static double charge(double progress) =>
      progress >= 0.7 ? 1 : Curves.easeIn.transform(progress / 0.7);

  static double pulse(double progress) {
    final phase = progress % 1;
    if (phase < 0.6) return 0.25;
    if (phase < 0.75) {
      return 0.25 + 0.75 * Curves.easeInOut.transform(_segment(phase, .6, .75));
    }
    return 1 - 0.75 * Curves.easeInOut.transform(_segment(phase, .75, 1));
  }
}
