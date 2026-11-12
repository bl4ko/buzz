import 'dart:math' show max, min;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'olympus_art.dart';
import 'olympus_colors.dart';
import 'olympus_hero.dart';
import 'olympus_scene_art.dart';
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
    // Cloud bitmaps are capped at 2x: three full-width layers at 3x cost 30 MB.
    final ratio = min(MediaQuery.devicePixelRatioOf(context), 2.0);
    final clouds = useRef(<int, OlympusSprite>{});
    final cloudsFor = useRef<(Size, double)?>(null);
    void release() {
      for (final cloud in clouds.value.values) {
        cloud.image.dispose();
      }
      clouds.value.clear();
    }

    useEffect(() => release, const []);
    OlympusSprite cloud(int index, Size size) {
      if (cloudsFor.value != (size, ratio)) {
        release();
        cloudsFor.value = (size, ratio);
      }
      return clouds.value[index] ??= _SkyPainter.rasterCloud(
        index,
        size,
        ratio,
      );
    }

    Widget layer({required bool front}) => IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _SkyPainter(
            clock: clock,
            reduced: reduced,
            hero: hero,
            sky: context,
            cloud: cloud,
            front: front,
          ),
        ),
      ),
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
            ExcludeSemantics(
              child: Opacity(
                key: const Key('scanner-scene-opacity'),
                opacity: 1 - progress,
                child: Transform.scale(
                  key: const Key('scanner-scene-scale'),
                  scale: reduced ? 1 : 1 - 0.04 * progress,
                  child: layer(front: false),
                ),
              ),
            ),
            Opacity(opacity: shown, alwaysIncludeSemantics: true, child: child),
            if (clock != null && !reduced) layer(front: true),
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
    required this.cloud,
    required this.front,
  }) : super(repaint: clock);

  final Animation<double>? clock;
  final bool reduced;
  final GlobalKey hero;
  final BuildContext sky;
  final OlympusSprite Function(int index, Size size) cloud;
  final bool front;

  static const _drift = [(-28.0, 50.0), (36.0, 40.0), (-48.0, 30.0)];
  static const _rise = [0.6, 0.7, 0.8];
  static const List<
    (double, double, List<(double?, double, double, double, double)>)
  >
  _wisps = [
    (26.0, 9.0, [(-1.5, -0.2, 1.5, 0.068, 0.34), (1.7, 0.5, 1.4, 0.063, 0.3)]),
    (19.0, 4.0, [(null, 0.62, 1.7, 0.079, 0.7)]),
    (24.0, 15.0, [(null, -0.5, 1.2, 0.058, 0.5)]),
  ];
  static final _gradient = ui.Gradient.linear(
    Offset.zero,
    const Offset(0, 1),
    const [Color(0xFF03041A), Color(0xFF0B0F38), Color(0xFF171C58)],
    const [0, 0.5, 1],
  );
  static final _aurora = OlympusArt.radial(
    [0x8C7A70F0, 0x384A4CC8, 0x003038A0],
    [0, 0.45, 1],
  );
  static final _sheet = OlympusArt.radial(
    [0xF2E9E6FF, 0x80A9A4FF, 0x007C78F0],
    [0, 0.35, 1],
  );
  static final _mist = OlympusArt.radial(
    [0x8CDCE2FF, 0x33B7C2F8, 0x00B7C2F8],
    [0, 0.6, 1],
  );
  static final _base = ui.Gradient.linear(
    const Offset(0, OlympusSceneArt.baseShade),
    Offset(0, OlympusSceneArt.size.height),
    const [Color(0x000A0E2E), Color(0xEB0A0E2E), Color(0xFF070A22)],
    const [0, 0.35, 1],
  );
  static final _strikes = [
    for (final strike in OlympusSceneArt.distantStrikes)
      () {
        final strokes = [
          for (final (points, width) in strike.strokes)
            (OlympusArt.polygon(points, close: false), width),
        ];
        final bounds = strokes
            .map((stroke) => stroke.$1.getBounds())
            .reduce((all, next) => all.expandToInclude(next))
            .inflate(16);
        return (
          period: strike.period,
          first: strike.first,
          strokes: strokes,
          glow: OlympusArt.raster(bounds, 1, (canvas) {
            for (final (path, width) in strokes) {
              canvas.drawPath(
                path,
                OlympusArt.line(0xFFB9C2FF, width * 3.6, 0.5)
                  ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
              );
            }
          }),
        );
      }(),
  ];

  static (double, Offset) _fit(Size size) {
    const art = OlympusSceneArt.size;
    final unit = max(size.height / art.height, size.width / 1100);
    return (
      unit,
      Offset(
        (size.width - art.width * unit) / 2,
        size.height - art.height * unit,
      ),
    );
  }

  static OlympusSprite rasterCloud(int index, Size size, double ratio) {
    final (unit, origin) = _fit(size);
    final art = OlympusSceneArt.clouds[index];
    final reach = _drift[index].$1.abs() * unit;
    return OlympusArt.raster(
      Rect.fromLTRB(
        -reach,
        max(0, origin.dy + (art.top - 8) * unit),
        size.width + reach,
        size.height,
      ),
      ratio,
      (canvas) {
        canvas
          ..translate(origin.dx, origin.dy)
          ..scale(unit);
        OlympusArt.paintCloud(canvas, art);
      },
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final clock = this.clock;
    final seconds = clock == null ? null : OlympusSceneClock.seconds(clock);
    final live = seconds != null && !reduced;
    double enter(
      double delay,
      double duration, [
      Curve curve = Curves.easeOut,
    ]) => seconds == null
        ? 1
        : reduced
        ? OlympusMotion.span(seconds, 0, 0.3)
        : OlympusMotion.span(seconds, delay, duration, curve);
    final box = hero.currentContext?.findRenderObject();
    final mark = box is RenderBox && box.hasSize
        ? OlympusHero.markRect(box.size).shift(
            box.localToGlobal(Offset.zero, ancestor: sky.findRenderObject()),
          )
        : null;
    final seal = mark == null
        ? null
        : mark.topLeft + Offset(0.5, 437 / 840) * mark.width;
    final radius = mark == null ? 0.0 : mark.width * 0.45;
    final (unit, origin) = _fit(size);
    void inArt(void Function() paint) {
      canvas
        ..save()
        ..translate(origin.dx, origin.dy)
        ..scale(unit);
      paint();
      canvas.restore();
    }

    void wisp(int index) {
      final (travel, phase, bands) = _wisps[index];
      final shift = live
          ? (1.9 * ((seconds + phase) / travel % 1) - 0.45) * size.width
          : 0.0;
      for (final (dx, dy, rx, ry, opacity) in bands) {
        OlympusArt.spot(
          canvas,
          Offset(
            (dx == null ? 0 : seal!.dx + dx * radius) + shift,
            seal!.dy + dy * radius,
          ),
          rx * radius,
          ry * radius,
          OlympusArt.faded(_mist, opacity * enter(1.1, 1.2)),
        );
      }
    }

    if (front) {
      if (seal != null) {
        wisp(1);
        wisp(2);
      }
      return;
    }

    void cloudLayer(int index) {
      final risen = enter(_rise[index], 0.9, OlympusMotion.settle);
      final (reach, period) = _drift[index];
      OlympusArt.sprite(
        canvas,
        cloud(index, size),
        opacity: risen,
        offset: live
            ? Offset(
                reach * unit * OlympusMotion.drift(seconds, period),
                44 * unit * (1 - risen),
              )
            : Offset.zero,
      );
    }

    canvas
      ..save()
      ..scale(size.width, size.height)
      ..drawRect(
        const Rect.fromLTWH(0, 0, 1, 1),
        OlympusArt.faded(_gradient, enter(0.3, 0.7)),
      )
      ..restore();
    if (seal != null) {
      final backdrop = enter(0.5, 1.2);
      inArt(() {
        for (final star in OlympusSceneArt.stars) {
          final twinkle = live && star.length > 4
              ? 0.22 + 0.78 * OlympusMotion.wave(seconds + star[5], star[4])
              : star[3];
          canvas.drawCircle(
            Offset(star[0], star[1]),
            star[2],
            Paint()
              ..color = OlympusColors.star.withValues(
                alpha: twinkle * backdrop,
              ),
          );
        }
      });
      cloudLayer(0);
      if (live) {
        inArt(() {
          for (final glow in OlympusSceneArt.sheetGlows) {
            final light = OlympusMotion.frames(
              OlympusMotion.since(seconds, glow[4], glow[3]),
              OlympusMotion.sheet,
            );
            if (light > 0) {
              OlympusArt.spot(
                canvas,
                Offset(glow[0], glow[1]),
                glow[2],
                glow[2],
                OlympusArt.faded(_sheet, light),
              );
            }
          }
        });
      }
      cloudLayer(1);
      if (live) {
        inArt(() {
          for (final strike in _strikes) {
            final elapsed = OlympusMotion.since(
              seconds,
              strike.first,
              strike.period,
            );
            final light = OlympusMotion.frames(elapsed, OlympusMotion.distant);
            if (light <= 0) continue;
            OlympusArt.sprite(canvas, strike.glow, opacity: light);
            for (final (path, width) in strike.strokes) {
              final metric = path.computeMetrics().first;
              canvas.drawPath(
                metric.extractPath(0, metric.length * min(1, elapsed / 70)),
                OlympusArt.line(0xFFFFFFFF, width, light),
              );
            }
          }
        });
      }
      OlympusArt.spot(
        canvas,
        seal,
        radius * 2.2,
        radius * 2.2,
        OlympusArt.faded(_aurora, 0.8 * backdrop),
      );
      wisp(0);
    }
    cloudLayer(2);
    final shade = enter(0.84, 0.9, OlympusMotion.settle);
    inArt(
      () => canvas
        ..translate(0, live ? 44 * (1 - shade) : 0)
        ..drawRect(
          Rect.fromLTRB(
            -2000,
            OlympusSceneArt.baseShade,
            2600,
            OlympusSceneArt.size.height + 400,
          ),
          OlympusArt.faded(_base, shade),
        ),
    );
  }

  @override
  bool shouldRepaint(_SkyPainter oldDelegate) => true;
}
