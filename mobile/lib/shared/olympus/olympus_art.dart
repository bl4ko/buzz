import 'dart:math' show max, min, pi;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

import 'olympus_colors.dart';

typedef OlympusGlow = ({ui.Image image, Rect bounds});

abstract final class OlympusArt {
  static const center = Offset(512, 468);
  static const ringRadius = 344.0;
  static const boltCenter = Offset(716, 342);
  static const markView = Rect.fromLTWH(92, 31, 840, 840);
  static const loaderView = Rect.fromLTWH(92, 48, 840, 840);
  static const inlineView = Rect.fromLTWH(548, 56, 332, 572);
  static const puffView = Rect.fromLTWH(-6, -30, 252, 140);
  static const launchExtent = 168.0;
  static const _glowScale = 0.5;

  static List<List<double>> table(String svg) => [
    for (final row in svg.split(' '))
      [for (final value in row.split(',')) double.parse(value)],
  ];

  static List<Offset> points(String svg) => [
    for (final point in table(svg)) Offset(point[0], point[1]),
  ];

  static Path polygon(String svg, {bool close = true}) =>
      Path()..addPolygon(points(svg), close);

  static Path cloud(String svg, [double? bottom]) {
    final rows = table(svg);
    final path = Path()..moveTo(rows.first[0], rows.first[1]);
    for (final arc in rows.skip(1)) {
      path.arcToPoint(Offset(arc[0], arc[1]), radius: Radius.circular(arc[2]));
    }
    if (bottom != null) {
      path
        ..lineTo(rows.last[0], bottom)
        ..lineTo(rows.first[0], bottom);
    }
    return path..close();
  }

  static ui.Gradient _vertical(
    double top,
    double bottom,
    List<int> colors, [
    List<double>? stops,
  ]) => ui.Gradient.linear(Offset(0, top), Offset(0, bottom), [
    for (final color in colors) Color(color),
  ], stops);

  static ui.Gradient _diagonal(List<int> colors, List<double> stops) =>
      ui.Gradient.linear(const Offset(150, 110), const Offset(870, 830), [
        for (final color in colors) Color(color),
      ], stops);

  static final ringGold = _diagonal(
    [0xFFFFEFA6, 0xFFF7C234, 0xFFE39A16, 0xFFB46A0C],
    [0, 0.35, 0.7, 1],
  );
  static final ringGoldLight = _diagonal(
    [0xFFF2B824, 0xFFD9930F, 0xFFB46A0C],
    [0, 0.6, 1],
  );

  static final bolt = polygon(
    '706,56 846,56 772,256 862,256 572,628 654,346 566,346',
  );
  static final _boltFold = polygon(
    '770,56 846,56 772,256 862,256 572,628 704,304',
  );
  static final boltSegments = [
    polygon('706,56 846,56 772,256 609,256'),
    polygon('609,256 862,256 792,346 566,346'),
    polygon('654,346 792,346 572,628'),
  ];
  static final _boltBounds = bolt.getBounds();

  static final _boltDark = _boltPicture(
    _vertical(56, 628, [0xFFFFFDF0, 0xFFFFF0B8, 0xFFFFD866], [0, 0.6, 1]),
    _vertical(56, 628, [0xFFFFDC5C, 0xFFF6B21E, 0xFFDC7C0C], [0, 0.5, 1]),
  );
  static final _boltLight = _boltPicture(
    _vertical(56, 628, [0xFFF9CC45, 0xFFEFA91A]),
    _vertical(56, 628, [0xFFE39A16, 0xFFB8690A]),
  );

  static final _discClip = Path()
    ..addOval(Rect.fromCircle(center: center, radius: ringRadius));
  static final _discPaint = Paint()
    ..shader = ui.Gradient.radial(
      const Offset(512, 372),
      400,
      const [Color(0xFF7A6CF2), Color(0xFF3E40B0), Color(0xFF151C56)],
      const [0, 0.45, 1],
    );
  static const _discStars = [
    (477.0, 234.0, 2.5, 0.50, 2.8, 4.33),
    (478.0, 354.0, 3.0, 0.70, 4.1, 1.67),
    (398.0, 406.0, 3.0, 0.92, 5.0, 4.76),
    (785.0, 501.0, 3.0, 0.51, 2.7, 2.53),
    (252.0, 452.0, 2.0, 0.82, 4.5, 0.51),
    (428.0, 506.0, 3.0, 0.48, 4.6, 4.45),
    (263.0, 423.0, 2.0, 0.93, 3.4, 0.22),
    (227.0, 483.0, 3.0, 0.40, 2.5, 2.12),
    (509.0, 519.0, 3.0, 0.44, 4.8, 1.65),
    (221.0, 438.0, 4.5, 0.48, 3.8, 2.86),
    (685.0, 483.0, 3.0, 0.81, 4.2, 0.47),
    (517.0, 423.0, 4.5, 0.72, 5.1, 0.27),
  ];
  static final _discRidge = polygon(
    '150,800 250,650 310,700 390,610 470,680 700,640 760,590 840,680 880,800',
  );

  static const _apex = '512,236';
  static const _silhouetteRight = '606,402 636,388 770,628 800,618 948,940';
  static const _spine = '544,420 500,590 560,940';
  static const _snowLit =
      '$_apex 405,436 442,412 468,456 500,406 524,452 544,420';
  static const _snowShade =
      '$_apex 606,402 636,388 658,428 626,448 602,416 574,460 544,420';
  static final _faceRight = polygon(
    '$_apex $_silhouetteRight 560,940 500,590 544,420',
  );
  static final _snow = Path()
    ..addPath(polygon(_snowLit), Offset.zero)
    ..addPath(polygon(_snowShade), Offset.zero);
  static final _rim = polygon('$_apex 606,402 636,388 770,628', close: false);

  static final _mountain = _record((canvas) {
    Paint fill(int color, double opacity) =>
        Paint()..color = Color(color).withValues(alpha: opacity);
    canvas
      ..drawPath(
        polygon('86,940 270,640 306,622 $_apex $_spine'),
        Paint()
          ..shader = _vertical(
            236,
            940,
            [0xFF93A8F6, 0xFF5068CA, 0xFF2A3A8E],
            [0, 0.45, 1],
          ),
      )
      ..drawPath(
        _faceRight,
        Paint()
          ..shader = _vertical(
            236,
            940,
            [0xFF34459A, 0xFF1C2760, 0xFF101742],
            [0, 0.5, 1],
          ),
      )
      ..drawPath(
        polygon('306,622 432,486 396,720 250,940 86,940 270,640'),
        fill(0xFF22327E, 0.55),
      )
      ..drawPath(
        polygon('$_apex 544,420 500,590 432,486'),
        fill(0xFFB4C3FF, 0.34),
      )
      ..drawPath(
        polygon('636,388 770,628 704,940 560,940 500,590 612,572'),
        fill(0xFF4257B0, 0.34),
      )
      ..drawPath(
        polygon('$_apex 544,420 500,590', close: false),
        fill(0xFFE6ECFF, 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeJoin = StrokeJoin.round,
      )
      ..drawPath(
        polygon(_snowLit),
        Paint()..shader = _vertical(236, 460, [0xFFFFFFFF, 0xFFF3E8CC]),
      )
      ..drawPath(
        polygon(_snowShade),
        Paint()..shader = _vertical(236, 460, [0xFFD3DBFA, 0xFF8A9CE0]),
      );
  });

  static final _cloudBackPath = cloud(
    '190,730 262,676,52 352,664,56 446,690,52 540,668,56 636,684,54 '
    '728,662,56 834,730,62',
    800,
  );
  static final _cloudFrontPath = cloud(
    '200,780 292,716,60 392,728,62 500,738,64 604,720,62 712,734,64 '
    '824,780,68',
    800,
  );
  static final puffPath = cloud(
    '0,100 40,56,40 112,30,52 190,58,46 232,100,34',
  );
  static final _cloudBack = _litCloud(
    _cloudBackPath,
    0xFFB7C2F8,
    _vertical(640, 790, [0xFF8E9DE6, 0xFF4C5CB4]),
    7,
  );
  static final _cloudFront = _litCloud(
    _cloudFrontPath,
    0xFFFFFFFF,
    _vertical(700, 790, [0xFFFFFCF2, 0xFFF4E9CE, 0xFFC9CFF0], [0, 0.6, 1]),
    7,
  );
  static final puff = _litCloud(
    puffPath,
    0xFFFFFFFF,
    _vertical(0, 100, [0xFFFFFCF2, 0xFFF1E6CC, 0xFFA9B4E8], [0, 0.55, 1]),
    6,
  );

  static final _ring = _record((canvas) {
    Paint stroke(double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    canvas
      ..drawCircle(center, ringRadius, stroke(68)..shader = ringGold)
      ..drawCircle(center, 375, stroke(3)..color = const Color(0xB3FFF6C8))
      ..drawCircle(center, 313, stroke(5)..color = const Color(0x8C8A4B06));
  });
  static final _meander = () {
    const units = 28;
    final path = Path();
    Rect ring(double radius) => Rect.fromCircle(center: center, radius: radius);
    Offset at(double radius, double angle) =>
        center + Offset.fromDirection(angle, radius);
    for (var unit = 0; unit < units; unit++) {
      const step = 2 * pi / units;
      final start = step * unit - pi / 2;
      path
        ..moveTo(at(326, start).dx, at(326, start).dy)
        ..arcTo(ring(362), start, step * 0.7, false)
        ..arcTo(ring(338), start + step * 0.7, -step * 0.38, false)
        ..lineTo(
          at(350, start + step * 0.32).dx,
          at(350, start + step * 0.32).dy,
        );
    }
    return path;
  }();
  static final _meanderPaint = Paint()
    ..color = const Color(0xD17E4505)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 7;

  static final _branchesA = Path()
    ..addPath(
      polygon('566,346 548,318 556,290 530,262 512,236', close: false),
      Offset.zero,
    )
    ..addPath(
      polygon('572,628 556,668 574,700 548,742 562,778', close: false),
      Offset.zero,
    )
    ..addPath(
      polygon('862,256 884,300 870,336 900,372', close: false),
      Offset.zero,
    );
  static final _branchesB = Path()
    ..addPath(
      polygon('706,56 684,78 694,98 660,112', close: false),
      Offset.zero,
    )
    ..addPath(
      polygon('572,628 600,664 584,694 616,730', close: false),
      Offset.zero,
    );

  static final _halo = _blurred(
    Rect.fromCircle(center: center, radius: 480),
    30,
    (canvas, paint) => canvas.drawCircle(
      center,
      ringRadius,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 68,
    ),
  );
  static final boltGlow = _blurred(
    _boltBounds.inflate(100),
    30,
    (canvas, paint) => canvas.drawPath(bolt, paint),
  );
  static final _boltShadow = _blurred(
    _boltBounds.inflate(32),
    8,
    (canvas, paint) => canvas.drawPath(bolt, paint),
  );
  static final _branchGlowA = _branchGlow(_branchesA);
  static final _branchGlowB = _branchGlow(_branchesB);
  static final ghost = _blurred(
    puffView,
    8,
    (canvas, paint) => canvas.drawPath(puffPath, paint),
  );

  static ui.Picture _record(void Function(Canvas canvas) paint) {
    final recorder = ui.PictureRecorder();
    paint(Canvas(recorder));
    return recorder.endRecording();
  }

  static ui.Picture _boltPicture(ui.Gradient face, ui.Gradient fold) => _record(
    (canvas) => canvas
      ..drawPath(bolt, Paint()..shader = face)
      ..drawPath(_boltFold, Paint()..shader = fold),
  );

  static ui.Picture _litCloud(
    Path path,
    int rim,
    ui.Gradient fill,
    double drop,
  ) => _record(
    (canvas) => canvas
      ..drawPath(path, Paint()..color = Color(rim))
      ..translate(0, drop)
      ..drawPath(path, Paint()..shader = fill),
  );

  static ui.Image raster(
    Rect bounds,
    double scale,
    void Function(Canvas canvas) paint,
  ) {
    final picture = _record((canvas) {
      canvas
        ..scale(scale)
        ..translate(-bounds.left, -bounds.top);
      paint(canvas);
    });
    final image = picture.toImageSync(
      (bounds.width * scale).ceil(),
      (bounds.height * scale).ceil(),
    );
    picture.dispose();
    return image;
  }

  static OlympusGlow _blurred(
    Rect bounds,
    double sigma,
    void Function(Canvas canvas, Paint paint) draw,
  ) => (
    image: raster(
      bounds,
      _glowScale,
      (canvas) => draw(
        canvas,
        Paint()
          ..color = OlympusColors.white
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
      ),
    ),
    bounds: bounds,
  );

  static OlympusGlow _branchGlow(Path branches) => _blurred(
    branches.getBounds().inflate(40),
    8,
    (canvas, paint) => canvas.drawPath(
      branches,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    ),
  );

  static void glow(
    Canvas canvas,
    OlympusGlow glow,
    Color color,
    double opacity, [
    Offset offset = Offset.zero,
  ]) {
    if (opacity <= 0) return;
    final image = glow.image;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      glow.bounds.shift(offset),
      Paint()
        ..color = OlympusColors.white.withValues(alpha: opacity)
        ..colorFilter = ColorFilter.mode(color, BlendMode.modulate)
        ..filterQuality = FilterQuality.low,
    );
  }

  static void fit(Canvas canvas, Rect view, Size size) {
    final scale = size.height / view.height;
    canvas
      ..translate((size.width - view.width * scale) / 2, 0)
      ..scale(scale)
      ..translate(-view.left, -view.top);
  }

  static void scaleAbout(Canvas canvas, Offset origin, double scale) => canvas
    ..translate(origin.dx, origin.dy)
    ..scale(scale)
    ..translate(-origin.dx, -origin.dy);

  static void loaderBolt(Canvas canvas) => canvas
    ..translate(center.dx, center.dy)
    ..scale(0.78)
    ..translate(-714, -342);

  static void paintBolt(
    Canvas canvas, {
    bool light = false,
    double opacity = 1,
  }) {
    if (opacity < 1) {
      canvas.saveLayer(
        _boltBounds,
        Paint()..color = OlympusColors.white.withValues(alpha: opacity),
      );
    }
    canvas.drawPicture(light ? _boltLight : _boltDark);
    if (opacity < 1) canvas.restore();
  }

  static void paintMedallion(
    Canvas canvas,
    double? seconds, {
    double? pulse,
    bool engraving = true,
  }) {
    final strike = seconds == null ? null : OlympusMotion.strike(seconds);
    final light = strike?.light ?? 0;
    final settled = seconds == null
        ? 0.0
        : OlympusMotion.span(seconds, 0.5, 1.2);
    double sway(double period) =>
        seconds == null ? 0 : OlympusMotion.drift(seconds + period / 2, period);
    Paint wash(int color, double opacity) =>
        Paint()..color = Color(color).withValues(alpha: opacity * light);

    glow(
      canvas,
      _halo,
      OlympusColors.glow,
      seconds == null
          ? pulse ?? 0
          : (0.42 + 0.22 * OlympusMotion.wave(seconds, 6)) * settled,
    );
    canvas.drawCircle(center, 314, _discPaint);
    for (final (x, y, radius, rest, period, phase) in _discStars) {
      final twinkle = seconds == null
          ? rest
          : 0.2 + 0.8 * OlympusMotion.wave(seconds + phase, period);
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..color = OlympusColors.star.withValues(
            alpha: rest + (twinkle - rest) * settled,
          ),
      );
    }

    canvas
      ..save()
      ..clipPath(_discClip);
    if (settled > 0) {
      canvas
        ..save()
        ..translate(10 * sway(22), 0)
        ..drawPath(
          _discRidge,
          Paint()
            ..color = const Color(0xFF2A3690).withValues(alpha: 0.75 * settled),
        )
        ..restore();
    }
    canvas.drawPicture(_mountain);
    if (light > 0) {
      canvas
        ..drawPath(_faceRight, wash(0xFFFFD27A, 0.2))
        ..drawPath(_snow, wash(0xFFFFFFFF, 1))
        ..drawPath(
          _rim,
          wash(0xFFFFE7A0, 1)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9
            ..strokeJoin = StrokeJoin.round,
        );
    }
    canvas
      ..save()
      ..translate(16 * sway(18), 0)
      ..drawPicture(_cloudBack);
    if (light > 0) canvas.drawPath(_cloudBackPath, wash(0xFFDCE2FF, 0.55));
    canvas
      ..restore()
      ..save()
      ..translate(-20 * sway(14), 0)
      ..drawPicture(_cloudFront);
    if (light > 0) canvas.drawPath(_cloudFrontPath, wash(0xFFFFF3C8, 0.7));
    canvas
      ..restore()
      ..restore();
    // The launch image has the halo over the disc; it fades to the scene halo.
    glow(
      canvas,
      _halo,
      OlympusColors.glow,
      seconds == null && pulse != null ? 0 : 0.5 * (1 - settled),
    );
    canvas.drawPicture(_ring);

    if (engraving) {
      canvas
        ..save()
        ..translate(center.dx, center.dy)
        ..rotate(seconds == null ? 0 : 2 * pi * seconds / 120)
        ..translate(-center.dx, -center.dy)
        ..drawPath(_meander, _meanderPaint)
        ..restore();
    }
    if (light > 0) {
      canvas.drawCircle(
        center,
        ringRadius,
        wash(0xFFFFF8D8, 0.55 * 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 68,
      );
    }
    if (strike != null) {
      _paintBranches(canvas, _branchesA, _branchGlowA, strike.a, 1);
      _paintBranches(canvas, _branchesB, _branchGlowB, strike.b, 0.8);
    }

    canvas.save();
    if (seconds != null) {
      canvas.translate(0, -8 * OlympusMotion.wave(seconds, 5));
      scaleAbout(canvas, boltCenter, strike!.punch);
    }
    // The phase makes the loop start at the launch image glow of 0.9.
    glow(
      canvas,
      boltGlow,
      OlympusColors.boltGlow,
      seconds == null
          ? 0.9
          : 0.7 + 0.3 * OlympusMotion.wave(seconds + 1.92, 3.2),
    );
    glow(
      canvas,
      _boltShadow,
      const Color(0xFF070B24),
      0.55,
      const Offset(12, 16),
    );
    paintBolt(canvas);
    glow(canvas, boltGlow, OlympusColors.white, 0.9 * light);
    if (light > 0) canvas.drawPath(bolt, wash(0xFFFFFFFF, 1));
    canvas.restore();
  }

  static void _paintBranches(
    Canvas canvas,
    Path branches,
    OlympusGlow glowImage,
    double elapsed,
    double strength,
  ) {
    if (elapsed <= 0 || elapsed >= 360) return;
    final opacity = strength * (elapsed < 225 ? 1 : (360 - elapsed) / 135);
    glow(canvas, glowImage, const Color(0xFFFFC83A), 0.85 * opacity);
    final paint = Paint()
      ..color = const Color(0xFFFFFDF0).withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    for (final metric in branches.computeMetrics()) {
      canvas.drawPath(
        metric.extractPath(0, metric.length * min(1, elapsed / 81)),
        paint,
      );
    }
  }
}

abstract final class OlympusMotion {
  static const cycle = Duration(days: 1);
  static const settle = Cubic(0.22, 1, 0.36, 1);
  static const _flashTail = Cubic(0.2, 0.6, 0.3, 1);
  static const _flashA = [
    (36.0, 1.0),
    (108.0, 0.25),
    (180.0, 1.0),
    (288.0, 0.7),
    (900.0, 0.0),
  ];
  static const _flashB = [
    (39.0, 0.6),
    (117.0, 0.15),
    (195.0, 0.6),
    (780.0, 0.0),
  ];
  static const _punchA = [(54.0, 0.07), (270.0, -0.01), (540.0, 0.0)];
  static const _punchB = [(52.0, 0.04), (260.0, 0.0)];

  static double span(
    double seconds,
    double delay,
    double duration, [
    Curve curve = Curves.easeOut,
  ]) => curve.transform(((seconds - delay) / duration).clamp(0.0, 1.0));

  static double wave(double seconds, double period) {
    final phase = seconds / period % 2;
    return Curves.easeInOut.transform(phase < 1 ? phase : 2 - phase);
  }

  static double drift(double seconds, double period) =>
      wave(seconds, period) * 2 - 1;

  static double keys(
    double at,
    List<(double, double)> frames, [
    Curve tail = Curves.linear,
  ]) {
    if (at <= 0) return 0;
    var (from, value) = (0.0, 0.0);
    for (final (to, next) in frames) {
      if (at < to) {
        final progress = (at - from) / (to - from);
        return value +
            (next - value) *
                (to == frames.last.$1 ? tail.transform(progress) : progress);
      }
      (from, value) = (to, next);
    }
    return 0;
  }

  static ({double a, double b, double light, double word, double punch}) strike(
    double seconds,
  ) {
    final a = seconds < 6.4
        ? (seconds - 0.95) * 1000
        : (seconds - 6.4) % 9 * 1000;
    final b = seconds < 11.03 ? -1.0 : (seconds - 11.03) % 13 * 1000;
    final flashA = keys(a, _flashA, _flashTail);
    return (
      a: a,
      b: b,
      light: max(flashA, keys(b, _flashB, _flashTail)),
      word: seconds < 6.4 ? 0 : 0.7 * flashA,
      punch: (1 + keys(a, _punchA)) * (1 + keys(b, _punchB)),
    );
  }

  static double flash(double seconds) => strike(seconds).light;
}
