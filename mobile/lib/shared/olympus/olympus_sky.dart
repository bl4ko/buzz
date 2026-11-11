import 'dart:math' show max;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'olympus_art.dart';
import 'olympus_colors.dart';
import 'olympus_hero.dart';
import 'olympus_scene_clock.dart';
import 'use_olympus_reduced_motion.dart';

class OlympusSky extends HookWidget {
  const OlympusSky({
    super.key,
    required this.child,
    this.animated = false,
    this.scannerProgress = const AlwaysStoppedAnimation(0),
  });

  final Widget child;
  final bool animated;
  final ValueListenable<double> scannerProgress;

  @override
  Widget build(BuildContext context) {
    final reduced = useOlympusReducedMotion(context);
    final lifecycle = useAppLifecycleState();
    final progress = useValueListenable(scannerProgress);
    final controller = useAnimationController(duration: OlympusMotion.cycle);
    final hero = useMemoized(GlobalKey.new);
    final moving = animated && !MediaQuery.disableAnimationsOf(context);
    final playing =
        moving &&
        progress < 1 &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
    useEffect(() {
      playing ? controller.repeat() : controller.stop();
      return null;
    }, [controller, playing]);
    final clock = moving ? controller : null;
    // Rebuilds, and so repaints the aurora, when the keyboard moves the hero.
    MediaQuery.viewInsetsOf(context);
    final shown = useListenableSelector(
      reduced ? clock : null,
      () => reduced && clock != null
          ? OlympusMotion.span(OlympusSceneClock.seconds(clock), 0, 0.3)
          : 1.0,
    );
    return OlympusSceneClock(
      clock: clock,
      reduced: reduced,
      hero: hero,
      child: ColoredBox(
        key: const Key('olympus-sky'),
        color: OlympusColors.navy,
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: ExcludeSemantics(
                child: Opacity(
                  key: const Key('scanner-scene-opacity'),
                  opacity: 1 - progress,
                  child: Transform.scale(
                    key: const Key('scanner-scene-scale'),
                    scale: reduced ? 1 : 1 - 0.04 * progress,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _SkyPainter(
                          clock: clock,
                          reduced: reduced,
                          hero: hero,
                          sky: context,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Opacity(opacity: shown, alwaysIncludeSemantics: true, child: child),
          ],
        ),
      ),
    );
  }
}

class _SkyPainter extends CustomPainter {
  _SkyPainter({
    required this.clock,
    required this.reduced,
    required this.hero,
    required this.sky,
  }) : super(repaint: clock);

  final Animation<double>? clock;
  final bool reduced;
  final GlobalKey hero;
  final BuildContext sky;

  static const _unit = Rect.fromLTRB(-1, -1, 1, 1);
  static final _gradient = ui.Gradient.linear(
    Offset.zero,
    const Offset(0, 1),
    const [Color(0xFF050818), Color(0xFF0E1640), Color(0xFF1F2970)],
    const [0, 0.55, 1],
  );
  static final _aurora = ui.Gradient.radial(
    Offset.zero,
    1,
    const [Color(0x5C6E62E6), Color(0x213E40B0), Color(0x003E40B0)],
    const [0, 0.55, 1],
  );
  static final _flash = ui.Gradient.radial(
    Offset.zero,
    1,
    const [Color(0x57D6DAFF), Color(0x217882FF), Color(0x007882FF)],
    const [0, 0.4, 0.72],
  );
  static final _fog = ui.Gradient.linear(
    Offset.zero,
    const Offset(0, 170),
    const [Color(0x005A6BD0), Color(0x295A6BD0), Color(0x005A6BD0)],
    const [0, 0.5, 1],
  );
  static final _stars = OlympusArt.table(
    '.178,.437,2.5,3.2,4.22 .97,.31,2,2.9,2.64 .777,.038,2,3.6,.72 '
    '.741,.574,2.5,2.5,4.99 .729,.546,2,3.6,4.78 .539,.439,2.5,5.1,1.84 '
    '.169,.512,1,4.7,.1 .175,.46,1.5,3.8,.93 .056,.541,1,2.6,.99 '
    '.667,.504,2.5,4.5,3.81 .578,.461,1,4,2.79 .392,.231,1,4.9,2.05 '
    '.371,.296,1.5,3.3,2.42 .275,.522,1,4.4,4.96 .496,.32,2,4.1,2.61 '
    '.569,.218,2,2.7,3.35 .621,.522,1.5,3.4,2.99 .314,.091,1,5,.87 '
    '.432,.124,1,4.3,4.49 .94,.27,1,5.1,2.95 .868,.32,1.5,4.3,4.68 '
    '.256,.361,1.5,4.7,3.87 .484,.524,1,4.8,3.29 .053,.177,1.5,2.6,1.69 '
    '.883,.61,2.5,4.4,.25 .154,.414,2.5,3.7,4.76 .883,.246,1,4.9,3.01 '
    '.429,.373,1.5,3.3,2.67 .285,.483,1,3.5,.63 .707,.186,1.5,4.2,4.26 '
    '.581,.182,1.5,4.5,4.06 .153,.114,1.5,2.7,.13 .449,.113,1,4.2,.63 '
    '.537,.221,1.5,4.9,3.11 .194,.536,1,4.4,2.75 .064,.449,2.5,4.6,3.95 '
    '.028,.304,1,3.5,2.83 .84,.168,2.5,4.1,3.73 .255,.122,2.5,4.9,1.48 '
    '.503,.354,2,2.7,3.01 .508,.463,2,3.3,3.5 .525,.361,1,4.1,1.63 '
    '.213,.069,2.5,5.2,.54 .093,.073,1.5,3.8,4.74',
  );
  static const _ghosts = [
    (0.12, 0.26, 0.16, 110.0, 30.0),
    (0.31, 0.18, 0.11, 150.0, 95.0),
    (0.05, 0.34, 0.09, 140.0, 70.0),
  ];
  static const _far =
      '-120,400 -120,80 -73,108 -16,201 22,222 53,177 89,143 114,110 186,181 '
      '236,200 297,251 345,192 381,144 434,92 493,124 525,178 587,227 617,185 '
      '653,123 686,81 739,136 769,179 813,257 863,212 904,197 955,151 '
      '1008,174 1082,195 1129,224 1157,192 1205,163 1236,133 1286,161 '
      '1340,205 1405,253 1443,219 1510,151 1549,79 1608,165 1643,166 1708,245 '
      '1713,238 1716,234 1720,223 1720,400';
  static final _farRim = Path()
    ..addPolygon(
      OlympusArt.points(_far).sublist(1, OlympusArt.points(_far).length - 1),
      false,
    );
  static final _ridges = [
    (
      OlympusArt.polygon(_far),
      _ridgeFill(80, 0xFF303C8C, 0xFF1A2360),
      0.6,
      12.0,
      30.0,
      230.0,
    ),
    (
      OlympusArt.polygon(
        '-120,400 -120,234 -69,249 -6,268 67,295 101,257 134,226 164,213 '
        '205,253 259,279 311,318 364,287 409,248 462,230 527,273 593,296 '
        '638,313 671,279 713,252 746,218 783,237 833,285 882,322 920,293 '
        '941,285 983,246 1024,269 1062,287 1110,314 1149,291 1184,256 1233,215 '
        '1291,241 1354,255 1437,291 1468,281 1497,268 1538,254 1587,262 '
        '1651,286 1709,293 1713,307 1716,316 1720,323 1720,400',
      ),
      _ridgeFill(190, 0xFF1E2866, 0xFF111846),
      0.72,
      -24.0,
      24.0,
      300.0,
    ),
    (
      OlympusArt.polygon(
        '-120,400 -120,291 -65,306 11,344 73,367 127,344 158,311 205,291 '
        '273,333 309,343 381,369 433,353 464,344 514,322 596,331 667,341 '
        '737,353 780,339 844,322 904,307 974,339 1049,368 1099,375 1152,347 '
        '1181,309 1227,286 1317,313 1403,328 1481,360 1520,351 1575,324 '
        '1618,302 1646,319 1693,358 1720,374 1720,400',
      ),
      _ridgeFill(290, 0xFF121A46, 0xFF0A0F2C),
      0.84,
      40.0,
      18.0,
      null,
    ),
  ];

  static ui.Gradient _ridgeFill(double top, int from, int to) =>
      ui.Gradient.linear(Offset(0, top), const Offset(0, 400), [
        Color(from),
        Color(to),
      ]);

  static Paint _faded(ui.Gradient shader, double opacity) => Paint()
    ..shader = shader
    ..color = OlympusColors.white.withValues(alpha: opacity);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final clock = this.clock;
    final seconds = clock == null ? null : OlympusSceneClock.seconds(clock);
    final live = seconds != null && !reduced;
    final light = live ? OlympusMotion.flash(seconds) : 0.0;
    double enter(
      double delay,
      double duration, [
      Curve curve = Curves.easeOut,
    ]) => seconds == null
        ? 1
        : reduced
        ? OlympusMotion.span(seconds, 0, 0.3)
        : OlympusMotion.span(seconds, delay, duration, curve);
    final backdrop = enter(0.5, 1.2);
    final box = hero.currentContext?.findRenderObject();
    final frame = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero, ancestor: sky.findRenderObject()) &
              box.size
        : null;
    final mark = frame == null
        ? null
        : OlympusHero.markRect(frame.size).shift(frame.topLeft);

    canvas
      ..save()
      ..scale(size.width, size.height)
      ..drawRect(
        const Rect.fromLTWH(0, 0, 1, 1),
        _faded(_gradient, live ? OlympusMotion.span(seconds, 0.3, 0.7) : 1),
      )
      ..restore();
    if (mark != null) {
      canvas
        ..save()
        ..translate(mark.center.dx, mark.center.dy)
        ..scale(mark.width * 1.4)
        ..drawRect(_unit, _faded(_aurora, backdrop))
        ..restore();
    }
    if (mark != null) {
      final text = Rect.fromLTRB(
        0,
        mark.top + mark.width * 1.05,
        size.width,
        frame!.bottom + 64,
      );
      for (final star in _stars) {
        final center = Offset(star[0] * size.width, star[1] * size.height);
        if (text.contains(center)) continue;
        final twinkle = live
            ? 0.2 + 0.8 * OlympusMotion.wave(seconds + star[4], star[3])
            : 1.0;
        canvas.drawCircle(
          center,
          star[2],
          Paint()
            ..color = OlympusColors.star.withValues(alpha: twinkle * backdrop),
        );
      }
    }
    for (final (top, width, opacity, period, phase) in _ghosts) {
      final across = ((live ? seconds : 0) + phase) / period % 1;
      final extent = width * size.width;
      canvas
        ..save()
        ..translate((5.3 * across - 1.3) * extent, top * size.height)
        ..scale(extent / OlympusArt.puffView.width)
        ..translate(-OlympusArt.puffView.left, -OlympusArt.puffView.top);
      OlympusArt.glow(
        canvas,
        OlympusArt.ghost,
        OlympusColors.cloudShadow,
        opacity * backdrop,
      );
      canvas.restore();
    }

    final scale = max(size.width / 1600, size.height * 0.34 / 400);
    canvas
      ..save()
      ..translate((size.width - 1600 * scale) / 2, size.height - 400 * scale)
      ..scale(scale);
    for (final (ridge, fill, delay, sway, period, fog) in _ridges) {
      final risen = enter(delay, 0.9, OlympusMotion.settle);
      canvas
        ..save()
        ..translate(
          live ? sway * OlympusMotion.drift(seconds, period) : 0,
          live ? 48 * (1 - risen) : 0,
        )
        ..drawPath(ridge, _faded(fill, risen));
      if (ridge == _ridges.first.$1 && light > 0) {
        canvas.drawPath(
          _farRim,
          Paint()
            ..color = const Color(0xFFC9D3FF).withValues(alpha: 0.8 * light)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeJoin = StrokeJoin.round,
        );
      }
      canvas.restore();
      if (fog != null) {
        final haze = live ? 0.2 + 0.8 * OlympusMotion.wave(seconds, 9) : 1.0;
        canvas
          ..save()
          ..translate(0, fog)
          ..drawRect(
            const Rect.fromLTWH(0, 0, 1600, 170),
            _faded(_fog, haze * risen),
          )
          ..restore();
      }
    }
    canvas.restore();

    if (mark != null && light > 0) {
      final strike = mark.topLeft + Offset(0.743, 0.37) * mark.width;
      final reach = max(
        max(strike.distance, (strike - size.topRight(Offset.zero)).distance),
        max(
          (strike - size.bottomLeft(Offset.zero)).distance,
          (strike - size.bottomRight(Offset.zero)).distance,
        ),
      );
      canvas
        ..save()
        ..translate(strike.dx, strike.dy)
        ..scale(reach)
        ..drawRect(_unit, _faded(_flash, light))
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_SkyPainter oldDelegate) => true;
}
