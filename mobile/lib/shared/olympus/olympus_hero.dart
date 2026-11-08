import 'dart:math' show min;

import 'package:flutter/material.dart';

import 'olympus_art.dart';
import 'olympus_colors.dart';
import 'olympus_scene_clock.dart';

class OlympusHero extends StatelessWidget {
  const OlympusHero({super.key});

  @override
  Widget build(BuildContext context) {
    final clock = OlympusSceneClock.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final fontSize = constraints.maxWidth * 0.08;
        final letterSpacing = fontSize * 0.32;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CustomPaint(
                key: const Key('olympus-hero-mark'),
                painter: OlympusHeroPainter(clock),
              ),
            ),
            SizedBox(height: constraints.maxWidth * 0.04),
            Padding(
              padding: EdgeInsets.only(left: letterSpacing),
              child: Text(
                'OLYMPUS',
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontFamilyFallback: const ['Times New Roman', 'serif'],
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: letterSpacing,
                  height: 1.2,
                  color: OlympusColors.marble,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class OlympusHeroPainter extends CustomPainter {
  OlympusHeroPainter(this.clock) : super(repaint: clock);

  final Animation<double>? clock;

  static const _top = 40.0;
  static const _bottom = 960.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final clock = this.clock;
    final seconds = clock == null ? null : OlympusSceneClock.seconds(clock);
    final scale = min(size.height / (_bottom - _top), size.width / 1000);
    final flash = seconds == null ? 0.0 : OlympusMotion.flash(seconds);
    final bounds = (Offset.zero & size).inflate(size.width);
    if (flash > 0) canvas.saveLayer(bounds, Paint());
    canvas
      ..save()
      ..translate(size.width / 2 - 512 * scale, -_top * scale)
      ..scale(scale);
    OlympusArt.paintMountain(canvas);
    _paintBolt(canvas, seconds);
    double drift(double period) =>
        seconds == null ? 0 : OlympusMotion.drift(seconds, period);
    OlympusArt.paintFrontCloud(canvas, Offset(330 + drift(14) * 140, 835), 2.6);
    OlympusArt.paintFrontCloud(canvas, Offset(790 - drift(18) * 110, 700), 1.9);
    canvas.restore();
    if (flash > 0) {
      canvas
        ..drawRect(
          bounds,
          Paint()
            ..color = Colors.white.withValues(alpha: flash)
            ..blendMode = BlendMode.srcATop,
        )
        ..restore();
    }
  }

  void _paintBolt(Canvas canvas, double? seconds) {
    final strike = seconds == null
        ? (opacity: 1.0, lift: 0.0, scale: 1.0)
        : OlympusMotion.strike(seconds);
    if (strike.opacity <= 0) return;
    final center = OlympusArt.boltBounds.center;
    canvas
      ..save()
      ..translate(center.dx, center.dy - 60 * strike.lift)
      ..scale(strike.scale)
      ..translate(-center.dx, -center.dy)
      ..drawPath(
        OlympusArt.polygon(OlympusArt.bolt),
        Paint()..color = OlympusColors.gold.withValues(alpha: strike.opacity),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(OlympusHeroPainter oldDelegate) =>
      clock != oldDelegate.clock;
}
