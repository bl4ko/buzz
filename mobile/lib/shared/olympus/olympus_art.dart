import 'dart:math' show pi;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

import 'olympus_colors.dart';

typedef OlympusSprite = ({ui.Image image, Rect bounds});
typedef OlympusTone = ({
  List<int> fill,
  List<double> stops,
  int rim,
  int light,
  int shade,
});
typedef OlympusCloud = ({
  String lobes,
  String body,
  OlympusTone tone,
  double top,
  double span,
  double rim,
});
typedef _Bolt = ({
  double first,
  bool right,
  Offset middle,
  List<(Path, double, double, double)> strokes,
  OlympusSprite glow,
});

abstract final class OlympusArt {
  static const center = Offset(512, 468);
  static const ringRadius = 344.0;
  static const markView = Rect.fromLTWH(92, 31, 840, 840);
  static const launchExtent = 168.0;

  static const storm = (
    fill: [0xFF5A62AC, 0xFF30377A, 0xFF141848],
    stops: [0.0, 0.4, 1.0],
    rim: 0xFF8990DA,
    light: 0xFF8A92E0,
    shade: 0xFF0A0D30,
  );
  static const storm2 = (
    fill: [0xFF3C448C, 0xFF1E245E, 0xFF0C0F34],
    stops: [0.0, 0.4, 1.0],
    rim: 0xFF6068B8,
    light: 0xFF5E68BC,
    shade: 0xFF06081E,
  );
  static const storm3 = (
    fill: [0xFF262C68, 0xFF12163E, 0xFF070920],
    stops: [0.0, 0.4, 1.0],
    rim: 0xFF424A96,
    light: 0xFF3C4490,
    shade: 0xFF030414,
  );
  static const lav = (
    fill: [0xFFCCD2F8, 0xFF8591DC, 0xFF333F96],
    stops: [0.0, 0.4, 1.0],
    rim: 0xFFEEF0FF,
    light: 0xFFF2F3FF,
    shade: 0xFF28337E,
  );
  static const cream = (
    fill: [0xFFFFFDF4, 0xFFEFE6DA, 0xFF8C96DA, 0xFF141A52],
    stops: [0.0, 0.3, 0.62, 1.0],
    rim: 0xFFFFFFFF,
    light: 0xFFFFFFFF,
    shade: 0xFF5D69BE,
  );

  static List<List<double>> table(String svg) => [
    for (final row in svg.split(' '))
      [for (final value in row.split(',')) double.parse(value)],
  ];

  static List<Offset> points(String svg) => [
    for (final point in table(svg)) Offset(point[0], point[1]),
  ];

  static Path polygon(String svg, {bool close = true}) =>
      Path()..addPolygon(points(svg), close);

  static ui.Gradient vertical(
    double top,
    double bottom,
    List<int> colors, [
    List<double>? stops,
  ]) => ui.Gradient.linear(Offset(0, top), Offset(0, bottom), [
    for (final color in colors) Color(color),
  ], stops);

  static ui.Gradient radial(List<int> colors, List<double> stops) =>
      ui.Gradient.radial(Offset.zero, 1, [
        for (final color in colors) Color(color),
      ], stops);

  static Paint faded(ui.Gradient shader, double opacity) => Paint()
    ..shader = shader
    ..color = OlympusColors.white.withValues(alpha: opacity);

  static Paint line(int color, double width, [double opacity = 1]) => Paint()
    ..color = Color(color).withValues(alpha: opacity)
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  static void spot(
    Canvas canvas,
    Offset center,
    double radiusX,
    double radiusY,
    Paint paint,
  ) => canvas
    ..save()
    ..translate(center.dx, center.dy)
    ..scale(radiusX, radiusY)
    ..drawCircle(Offset.zero, 1, paint)
    ..restore();

  static ui.Picture _record(void Function(Canvas canvas) paint) {
    final recorder = ui.PictureRecorder();
    paint(Canvas(recorder));
    return recorder.endRecording();
  }

  static OlympusSprite raster(
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
    return (image: image, bounds: bounds);
  }

  static void sprite(
    Canvas canvas,
    OlympusSprite sprite, {
    double opacity = 1,
    Color tint = OlympusColors.white,
    Offset offset = Offset.zero,
  }) {
    if (opacity <= 0) return;
    final image = sprite.image;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      sprite.bounds.shift(offset),
      Paint()
        ..color = OlympusColors.white.withValues(alpha: opacity)
        ..colorFilter = ColorFilter.mode(tint, BlendMode.modulate)
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

  static void paintCloud(Canvas canvas, OlympusCloud cloud) {
    final lobes = table(cloud.lobes);
    final body = points(cloud.body);
    final tone = cloud.tone;
    final base = cloud.top + cloud.span;
    final fill = Paint()
      ..shader = vertical(cloud.top, base, tone.fill, tone.stops);
    final rim = Paint()..color = Color(tone.rim);
    final shade = Paint()
      ..shader = radial(
        [
          tone.shade & 0x8CFFFFFF,
          tone.shade & 0x33FFFFFF,
          tone.shade & 0xFFFFFF,
        ],
        const [0, 0.6, 1],
      );
    final light = Paint()
      ..shader = radial(
        [
          tone.light & 0x99FFFFFF,
          tone.light & 0x38FFFFFF,
          tone.light & 0xFFFFFF,
        ],
        const [0, 0.55, 1],
      );
    for (final lobe in lobes) {
      canvas.drawCircle(Offset(lobe[0], lobe[1] - cloud.rim), lobe[2], rim);
    }
    canvas.drawPath(Path()..addPolygon(body, true), fill);
    for (final lobe in lobes) {
      canvas.drawCircle(Offset(lobe[0], lobe[1]), lobe[2], fill);
    }
    for (final lobe in lobes) {
      final radius = lobe[2] * 0.95;
      spot(
        canvas,
        Offset(lobe[0] + lobe[2] * 0.12, lobe[1] + lobe[2] * 0.62),
        radius,
        radius,
        shade,
      );
    }
    for (final lobe in lobes) {
      final radius = lobe[2] * 0.78;
      spot(
        canvas,
        Offset(lobe[0] - lobe[2] * 0.16, lobe[1] - lobe[2] * 0.3),
        radius,
        radius,
        light,
      );
    }
    canvas.drawRect(
      Rect.fromLTRB(
        body.first.dx,
        cloud.top + cloud.span / 2,
        body.last.dx,
        body.last.dy,
      ),
      Paint()
        ..shader = vertical(cloud.top + cloud.span / 2, base, [
          tone.fill.last & 0xFFFFFF,
          tone.fill.last,
        ]),
    );
  }

  static final _halo = raster(
    Rect.fromCircle(center: center, radius: 480),
    0.5,
    (canvas) => canvas.drawCircle(
      center,
      ringRadius,
      Paint()
        ..color = OlympusColors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 68
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    ),
  );
  static final _discPaint = Paint()
    ..shader = ui.Gradient.radial(
      const Offset(512, 372),
      400,
      const [Color(0xFF7A6CF2), Color(0xFF3E40B0), Color(0xFF151C56)],
      const [0, 0.45, 1],
    );
  static final _discStars = table(
    '494,328,2.5,5.6 423,362,2.5,8.2 645,253,4.5,10 320,278,2.5,5.4 '
    '671,332,3.5,9 347,273,3.5,9.2 749,337,2.5,6.8 446,372,2.5,5 '
    '666,263,2.5,9.6 306,530,3,7.6 469,337,3,8.4 328,415,3,10.2',
  );
  static final _discRidge = polygon(
    '150,800 250,650 310,700 390,610 470,680 700,640 760,590 840,680 880,800',
  );
  static final _summitClip = Path()
    ..addOval(Rect.fromCircle(center: center, radius: ringRadius));
  static final _skyClip = Path()
    ..addOval(Rect.fromCircle(center: center, radius: 312));

  static const _apex = '512,236';
  static const _spine = '544,420 500,590 560,940';
  static final _snowLit = polygon(
    '$_apex 405,436 442,412 468,456 500,406 524,452 544,420',
  );
  static final _snowShade = polygon(
    '$_apex 606,402 636,388 658,428 626,448 602,416 574,460 544,420',
  );
  static final _edgeLeft = polygon('306,622 $_apex', close: false);
  static final _edgeRight = polygon(
    '$_apex 606,402 636,388 770,628',
    close: false,
  );

  static final _mountain = _record((canvas) {
    Paint fill(int color, double opacity) =>
        Paint()..color = Color(color).withValues(alpha: opacity);
    canvas
      ..drawPath(
        polygon('86,940 270,640 306,622 $_apex $_spine'),
        Paint()
          ..shader = vertical(
            236,
            940,
            [0xFF93A8F6, 0xFF5068CA, 0xFF2A3A8E],
            [0, 0.45, 1],
          ),
      )
      ..drawPath(
        polygon(
          '$_apex 606,402 636,388 770,628 800,618 948,940 560,940 500,590 '
          '544,420',
        ),
        Paint()
          ..shader = vertical(
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
        _snowLit,
        Paint()..shader = vertical(236, 460, [0xFFFFFFFF, 0xFFF3E8CC]),
      )
      ..drawPath(
        _snowShade,
        Paint()..shader = vertical(236, 460, [0xFFD3DBFA, 0xFF8A9CE0]),
      );
  });

  static final _cloudBack = raster(
    const Rect.fromLTRB(0, 660, 1024, 830),
    1,
    (canvas) => paintCloud(canvas, (
      lobes:
          '730,690,12 750,688,16 822,690,13 709,691,12 838,693,16 855,696,16 '
          '868,698,17 774,696,25 311,702,15 309,700,22 742,705,28 824,708,28 '
          '713,708,28 590,716,17 858,713,28 626,720,16 284,715,36 198,717,31 '
          '341,717,37 339,718,38 128,726,24 257,724,37 333,722,46 574,731,28 '
          '466,731,36 770,729,53 603,736,36 383,744,64 150,755,53 511,755,53 '
          '220,754,64 639,758,64',
      body:
          '12,820 12,755 150,755 220,754 284,715 333,722 383,744 466,731 '
          '511,755 574,731 603,736 639,758 713,708 742,705 770,729 824,708 '
          '858,713 996,713 996,820',
      tone: lav,
      top: 671,
      span: 147,
      rim: 5,
    )),
  );
  static final _cloudFront = raster(
    const Rect.fromLTRB(0, 720, 1024, 830),
    1,
    (canvas) => paintCloud(canvas, (
      lobes:
          '234,745,13 241,746,16 267,752,21 493,755,16 274,754,22 599,755,29 '
          '560,758,22 775,761,16 755,762,15 229,763,30 478,766,28 481,764,35 '
          '150,766,30 330,771,26 476,770,30 284,769,34 188,771,39 683,774,32 '
          '260,776,39 767,779,30 727,780,26 652,784,39 584,784,50 514,792,57 '
          '424,799,50 370,802,50 304,802,57 696,808,57 800,814,70',
      body:
          '0,820 0,766 150,766 188,771 229,763 260,776 304,802 370,802 '
          '424,799 476,770 514,792 584,784 652,784 696,808 767,779 800,814 '
          '950,814 950,820',
      tone: cream,
      top: 726,
      span: 160,
      rim: 5,
    )),
  );

  static final _ring = _record((canvas) {
    Paint stroke(double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    canvas
      ..drawCircle(
        center,
        ringRadius,
        stroke(68)
          ..shader = ui.Gradient.linear(
            const Offset(150, 110),
            const Offset(870, 830),
            const [
              Color(0xFFFFEFA6),
              Color(0xFFF7C234),
              Color(0xFFE39A16),
              Color(0xFFB46A0C),
            ],
            const [0, 0.35, 0.7, 1],
          ),
      )
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
      final end = at(350, start + step * 0.32);
      path
        ..moveTo(at(326, start).dx, at(326, start).dy)
        ..arcTo(ring(362), start, step * 0.7, false)
        ..arcTo(ring(338), start + step * 0.7, -step * 0.38, false)
        ..lineTo(end.dx, end.dy);
    }
    return path;
  }();
  static final _meanderPaint = Paint()
    ..color = const Color(0xD17E4505)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 7;

  static final _backGlow = radial(
    [0x9EF1EEFF, 0x52B9B0FF, 0x008E86FF],
    [0, 0.35, 1],
  );
  static final _flicker = radial(
    [0xE6F4F0FF, 0x73B8AEFF, 0x008A80F0],
    [0, 0.4, 1],
  );
  static final _flickers = table(
    '246,610,150,7.3,4.6 792,590,160,9.1,6.9 330,640,120,11.9,9.4',
  );
  static final _bolts = [
    _bolt(1.7, true, const Offset(606, 482), const [
      (
        '662.2,185.5 661.2,198.9 652.5,243 687.1,312.8 673.3,345.6 '
            '682.7,355.6 654.5,398.3 664.4,419 654.9,436.2 606.1,482.5 '
            '579.4,539.3 587.6,549 601.9,553.2 649.9,586.3 656.8,595.3 '
            '669.4,602.4 684.7,581.7 716,610',
        7.92,
        0,
        80,
      ),
      (
        '662.2,185.5 661.2,198.9 652.5,243 687.1,312.8 673.3,345.6 '
            '682.7,355.6 654.5,398.3 664.4,419 654.9,436.2 606.1,482.5 '
            '583.2,531.3',
        11,
        0,
        54.4,
      ),
      (
        '662.2,185.5 661.2,198.9 652.5,243 687.1,312.8 673.3,345.6 '
            '682.7,355.6 674.6,367.8',
        14.08,
        0,
        27.2,
      ),
      (
        '687.1,312.8 673.9,334.4 660.3,352 652,376.5 647.7,386 651.4,421.5 '
            '650.3,430.9 651,439 647.8,449.8 637,454 630.2,461.4 623.4,469.5',
        5.72,
        18.5,
        54.5,
      ),
      (
        '650.3,430.9 631.2,430.8 610.5,442.1 601.7,447.3 596.5,454.1 '
            '597.4,462.5 590,474.6 579.7,491.3 565,491',
        3.74,
        44.2,
        68.2,
      ),
      (
        '664.4,419 669.7,427.4 680.4,428.8 705.6,453.4 707.3,463.2 '
            '713.2,470.1 721.4,475.5 740.9,485 749.4,483.5',
        5.72,
        35.3,
        71.3,
      ),
      (
        '579.4,539.3 552.9,535.2 517,555.6 520.6,566.4 510.9,584.2 '
            '505.6,593.1 493.3,605.6 481.2,604.5 468.6,579.2',
        5.72,
        55.6,
        91.6,
      ),
      (
        '510.9,584.2 506.9,596.8 500.3,611 500,620 499.6,634.6 503.9,651.4 '
            '513.7,655.9 519.3,652.2',
        3.74,
        77,
        101,
      ),
    ]),
    _bolt(12.3, false, const Offset(234, 442), const [
      (
        '361.8,185.5 359.3,198.8 354.2,208.1 353.8,220.4 327.8,291.6 '
            '251.7,328.9 240.6,357.1 239.5,386.4 232.1,395.7 225.5,405.7 '
            '227.6,428 233.7,441.8 254.1,464.5 253.4,490.2 265.3,507.9 '
            '309.3,507.1 336,519.4 335.9,533.5 332.7,546.6 325.8,564.6 '
            '310.8,569.5 332,650',
        7.92,
        0,
        80,
      ),
      (
        '361.8,185.5 359.3,198.8 354.2,208.1 353.8,220.4 327.8,291.6 '
            '251.7,328.9 240.6,357.1 239.5,386.4 232.1,395.7 225.5,405.7 '
            '227.6,428 233.7,441.8 254.1,464.5 253.4,490.2 265.3,507.9 '
            '287.8,507.5',
        11,
        0,
        54.4,
      ),
      (
        '361.8,185.5 359.3,198.8 354.2,208.1 353.8,220.4 327.8,291.6 '
            '251.7,328.9 247.3,340.1',
        14.08,
        0,
        27.2,
      ),
      (
        '251.7,328.9 251.9,348.8 243.5,361 236.9,381.9 230.9,403.4 '
            '221.1,415.3 203.7,429.4 195.9,443 205,463.8',
        5.72,
        25.6,
        61.6,
      ),
      (
        '230.9,403.4 235.4,409.6 239.5,416.1 248.1,427.7 266.1,444.5 '
            '270.9,457.3 273.1,465.3 268.7,476.7 258.4,480.7 254.4,486.8 '
            '257.5,495.8',
        3.74,
        44,
        68,
      ),
      ('225.5,405.7 203.7,403 183,410.3 142.2,424.8', 5.72, 36.5, 72.5),
      (
        '253.4,490.2 261.2,497.9 266.2,505.2 283.8,521 304.8,531.9 '
            '316.1,536.5 327.8,553.4 331.1,563.1 344.1,579.4',
        5.72,
        48.7,
        84.7,
      ),
    ]),
  ];

  static _Bolt _bolt(
    double first,
    bool right,
    Offset middle,
    List<(String, double, double, double)> strokes,
  ) {
    final paths = [
      for (final (points, width, from, to) in strokes)
        (polygon(points, close: false), width, from, to),
    ];
    Paint soft(int color, double width, double opacity, double blur) =>
        line(color, width, opacity)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    return (
      first: first,
      right: right,
      middle: middle,
      strokes: paths,
      glow: raster(Rect.fromCircle(center: center, radius: 330), 0.5, (canvas) {
        canvas.drawPath(paths.first.$1, soft(0xFF9E92FF, 55, 0.38, 20));
        for (final (path, width, _, _) in paths) {
          canvas.drawPath(path, soft(0xFFCFC6FF, width * 3.4, 0.5, 9));
        }
        for (final (path, width, _, _) in paths.take(3)) {
          canvas.drawPath(path, soft(0xFFFFF3DA, width * 1.9, 0.55, 4));
        }
      }),
    );
  }

  static void paintSeal(
    Canvas canvas,
    double? seconds, {
    double? pulse,
    bool engraving = true,
  }) {
    double swing(double period) =>
        seconds == null ? 0 : OlympusMotion.swing(seconds, period);
    final strikes = [
      for (final bolt in _bolts)
        if (seconds != null)
          (
            bolt,
            OlympusMotion.since(seconds, bolt.first, 21),
            OlympusMotion.frames(
              OlympusMotion.since(seconds, bolt.first, 21),
              OlympusMotion.flash,
            ),
          ),
    ];

    sprite(
      canvas,
      _halo,
      tint: OlympusColors.glow,
      opacity: pulse ?? 0.5 + 0.12 * swing(12),
    );
    canvas.drawCircle(center, 314, _discPaint);
    for (final star in _discStars) {
      canvas.drawCircle(
        Offset(star[0], star[1]),
        star[2],
        Paint()
          ..color = OlympusColors.star.withValues(
            alpha: seconds == null
                ? 0.8
                : OlympusMotion.frames(
                    seconds / star[3] % 1,
                    OlympusMotion.twinkle,
                    Curves.easeInOut,
                  ),
          ),
      );
    }

    canvas
      ..save()
      ..clipPath(_summitClip);
    if (seconds != null) {
      canvas
        ..save()
        ..clipPath(_skyClip);
      for (final (bolt, elapsed, flash) in strikes) {
        if (flash > 0) {
          spot(canvas, bolt.middle, 250, 250, faded(_backGlow, flash));
          canvas.drawCircle(
            center,
            312,
            Paint()
              ..color = const Color(0xFFA9A0FF).withValues(alpha: 0.3 * flash),
          );
        }
        _paintBolt(canvas, bolt, elapsed);
      }
      for (final flicker in _flickers) {
        final light = OlympusMotion.frames(
          OlympusMotion.since(seconds, flicker[4], flicker[3]),
          OlympusMotion.flicker,
        );
        if (light > 0) {
          spot(
            canvas,
            Offset(flicker[0], flicker[1]),
            flicker[2],
            flicker[2],
            faded(_flicker, 0.75 * light),
          );
        }
      }
      canvas.restore();
    }
    canvas
      ..save()
      ..translate(10 * swing(44), 0)
      ..drawPath(_discRidge, Paint()..color = const Color(0xBF2A3690))
      ..restore()
      ..drawPicture(_mountain);
    for (final (bolt, _, flash) in strikes) {
      if (flash <= 0) continue;
      final right = bolt.right;
      Paint snow(double opacity) =>
          Paint()..color = const Color(0xFFF4F3FF).withValues(alpha: opacity);
      canvas
        ..drawPath(
          right ? _edgeRight : _edgeLeft,
          line(0xFFE9EAFF, 5, 0.9 * flash),
        )
        ..drawPath(right ? _snowShade : _snowLit, snow(0.6 * flash))
        ..drawPath(
          right ? _edgeLeft : _edgeRight,
          line(0xFFE9EAFF, 4, 0.5 * flash),
        )
        ..drawPath(right ? _snowLit : _snowShade, snow(0.3 * flash));
    }
    sprite(canvas, _cloudBack, offset: Offset(14 * swing(40), 0));
    sprite(canvas, _cloudFront, offset: Offset(-18 * swing(30), 0));
    canvas
      ..restore()
      ..drawPicture(_ring);

    if (engraving) {
      canvas
        ..save()
        ..translate(center.dx, center.dy)
        ..rotate(seconds == null ? 0 : 2 * pi * seconds / 120)
        ..translate(-center.dx, -center.dy)
        ..drawPath(_meander, _meanderPaint)
        ..restore();
    }
    for (final (_, _, flash) in strikes) {
      if (flash <= 0) continue;
      Paint ring(int color, double width, double opacity) => Paint()
        ..color = Color(color).withValues(alpha: opacity * 0.8 * flash)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width;
      canvas
        ..drawCircle(center, 314, ring(0xFFF1EEFF, 9, 1))
        ..drawCircle(center, ringRadius, ring(0xFFF4F2FF, 68, 0.2));
    }
  }

  static void _paintBolt(Canvas canvas, _Bolt bolt, double elapsed) {
    final shown = OlympusMotion.frames(elapsed, OlympusMotion.bolt);
    if (shown <= 0) return;
    final bounds = bolt.glow.bounds;
    if (shown < 1) {
      canvas.saveLayer(
        bounds,
        Paint()..color = OlympusColors.white.withValues(alpha: shown),
      );
    }
    sprite(canvas, bolt.glow);
    for (final (path, width, from, to) in bolt.strokes) {
      final drawn = ((elapsed - from) / (to - from)).clamp(0.0, 1.0);
      if (drawn <= 0) continue;
      final paint = line(0xFFFFFDF0, width);
      if (drawn >= 1) {
        canvas.drawPath(path, paint);
      } else {
        final metric = path.computeMetrics().first;
        canvas.drawPath(metric.extractPath(0, metric.length * drawn), paint);
      }
    }
    if (shown < 1) canvas.restore();
  }
}

abstract final class OlympusMotion {
  static const cycle = Duration(days: 1);
  static const settle = Cubic(0.22, 1, 0.36, 1);
  static const bolt = [
    (0.0, 0.0),
    (8.0, 1.0),
    (95.0, 1.0),
    (135.0, 0.22),
    (200.0, 0.95),
    (300.0, 0.6),
    (760.0, 0.0),
  ];
  static const flash = [
    (0.0, 0.0),
    (55.0, 1.0),
    (130.0, 0.2),
    (205.0, 1.0),
    (330.0, 0.5),
    (820.0, 0.0),
  ];
  static const flicker = [
    (0.0, 0.0),
    (50.0, 0.8),
    (120.0, 0.2),
    (190.0, 0.6),
    (520.0, 0.0),
  ];
  static const sheet = [
    (0.0, 0.0),
    (60.0, 0.9),
    (140.0, 0.2),
    (220.0, 0.7),
    (320.0, 0.1),
    (400.0, 0.5),
    (900.0, 0.0),
  ];
  static const distant = [
    (0.0, 0.0),
    (10.0, 1.0),
    (100.0, 0.3),
    (160.0, 1.0),
    (420.0, 0.0),
  ];
  static const twinkle = [(0.0, 0.8), (0.2, 1.0), (0.7, 0.22), (1.0, 0.8)];
  static const _swing = [(0.0, 0.0), (0.25, 1.0), (0.75, -1.0), (1.0, 0.0)];

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

  static double swing(double seconds, double period) =>
      frames(seconds / period % 1, _swing, Curves.easeInOut);

  static double since(double seconds, double first, double period) =>
      seconds < first ? -1 : (seconds - first) % period * 1000;

  static double frames(
    double at,
    List<(double, double)> keys, [
    Curve curve = Curves.linear,
  ]) {
    var (from, value) = keys.first;
    for (final (to, next) in keys.skip(1)) {
      if (at < to) {
        if (at <= from) return value;
        return value +
            (next - value) * curve.transform((at - from) / (to - from));
      }
      (from, value) = (to, next);
    }
    return value;
  }
}
