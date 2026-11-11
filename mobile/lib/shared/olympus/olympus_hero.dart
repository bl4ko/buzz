import 'dart:math' show min;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'olympus_art.dart';
import 'olympus_colors.dart';
import 'olympus_scene_clock.dart';

typedef OlympusWordmark = ({
  double extent,
  List<TextPainter> letters,
  List<Offset> offsets,
});

class OlympusHero extends HookWidget {
  const OlympusHero({super.key, required this.extent});

  final double extent;

  static const minExtent = 96.0;
  static const _wordmarkTop = 1.159;
  static const _fontSize = 0.128;
  static const _ruleTop = 1.353;
  static const _ruleWidth = 0.389;
  static const heightFactor = _ruleTop + _ruleWidth * 14 / 224;

  static OlympusWordmark _wordmark(double extent) {
    final fontSize = extent * _fontSize;
    final letters = [
      for (final letter in 'OLYMPUS'.split(''))
        TextPainter(
          text: TextSpan(
            text: letter,
            style: TextStyle(
              fontFamily: 'Iowan Old Style',
              fontFamilyFallback: const ['Palatino', 'Georgia', 'serif'],
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              height: 1,
              color: OlympusColors.marble,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];
    final spacing = fontSize * 0.42;
    final width = letters.fold(
      -spacing,
      (sum, letter) => sum + letter.width + spacing,
    );
    final offsets = <Offset>[];
    var x = (extent - width) / 2;
    for (final letter in letters) {
      offsets.add(Offset(x, extent * _wordmarkTop));
      x += letter.width + spacing;
    }
    return (extent: extent, letters: letters, offsets: offsets);
  }

  static Rect markRect(Size size) {
    final extent = min(size.width, size.height / heightFactor);
    return Rect.fromLTWH((size.width - extent) / 2, 0, extent, extent);
  }

  @override
  Widget build(BuildContext context) {
    final scene = OlympusSceneClock.of(context);
    final screen = MediaQuery.sizeOf(context);
    final held = useRef<OlympusWordmark?>(null);
    void release() {
      for (final letter in held.value?.letters ?? const <TextPainter>[]) {
        letter.dispose();
      }
      held.value = null;
    }

    useEffect(() => release, const []);
    return Semantics(
      label: 'Olympus',
      image: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: minExtent * heightFactor,
          maxHeight: extent * heightFactor,
        ),
        // Infinite height: a flexible parent shrinks the hero before it scrolls.
        child: CustomPaint(
          key: scene?.hero,
          size: Size(extent, double.infinity),
          painter: OlympusHeroPainter(
            clock: scene?.clock,
            reduced: scene?.reduced ?? false,
            wordmark: (extent) {
              if (held.value?.extent != extent) {
                release();
                held.value = _wordmark(extent);
              }
              return held.value!;
            },
            launch: () => (context.findRenderObject()! as RenderBox)
                .globalToLocal(screen.center(Offset.zero)),
          ),
        ),
      ),
    );
  }
}

class OlympusHeroPainter extends CustomPainter {
  OlympusHeroPainter({
    required this.clock,
    required this.reduced,
    required this.wordmark,
    required this.launch,
  }) : super(repaint: clock);

  final Animation<double>? clock;
  final bool reduced;
  final OlympusWordmark Function(double extent) wordmark;
  final Offset Function() launch;

  static const _letterIn = Cubic(0.2, 0.8, 0.2, 1);
  static final _rule = () {
    final path = Path()
      ..moveTo(0, 7)
      ..lineTo(60, 7)
      ..moveTo(164, 7)
      ..lineTo(224, 7);
    for (var x = 72.0; x < 152; x += 20) {
      path
        ..moveTo(x, 12)
        ..lineTo(x, 2)
        ..lineTo(x + 14, 2)
        ..lineTo(x + 14, 9)
        ..lineTo(x + 6, 9)
        ..lineTo(x + 6, 6)
        ..lineTo(x + 10, 6);
    }
    return path;
  }();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final mark = OlympusHero.markRect(size);
    final extent = mark.width;
    final wordmark = this.wordmark(extent);
    final clock = this.clock;
    final seconds = clock == null ? null : OlympusSceneClock.seconds(clock);
    final live = seconds != null && !reduced;

    canvas
      ..translate(mark.left, 0)
      ..save();
    if (live && seconds < 1.1) {
      final arrived = OlympusMotion.span(
        seconds,
        0.4,
        0.7,
        OlympusMotion.settle,
      );
      final rest = Offset(extent / 2, extent / 2);
      final shift = (launch() - mark.topLeft - rest) * (1 - arrived);
      canvas.translate(shift.dx, shift.dy);
      OlympusArt.scaleAbout(
        canvas,
        rest,
        ui.lerpDouble(OlympusArt.launchExtent / extent, 1, arrived)!,
      );
    }
    OlympusArt.fit(canvas, OlympusArt.markView, Size.square(extent));
    OlympusArt.paintSeal(
      canvas,
      live ? seconds : null,
      pulse: seconds == null || !reduced
          ? null
          : 0.38 + 0.24 * OlympusMotion.wave(seconds, 8),
      engraving: extent * 0.9 >= 120,
    );
    canvas.restore();

    final fontSize = extent * OlympusHero._fontSize;
    for (final (index, letter) in wordmark.letters.indexed) {
      final shown = live
          ? OlympusMotion.span(seconds, 1 + 0.06 * index, 0.52, _letterIn)
          : 1.0;
      if (shown <= 0) continue;
      final offset = wordmark.offsets[index];
      if (shown < 1) {
        final box = offset & letter.size;
        canvas
          ..saveLayer(
            box.inflate(fontSize),
            Paint()..color = OlympusColors.white.withValues(alpha: shown),
          )
          ..translate(0, fontSize * 0.35 * (1 - shown));
        OlympusArt.scaleAbout(canvas, box.center, 0.96 + 0.04 * shown);
      }
      letter.paint(canvas, offset);
      if (shown < 1) canvas.restore();
    }

    final ruled = live
        ? OlympusMotion.span(seconds, 1.5, 0.6, OlympusMotion.settle)
        : 1.0;
    if (ruled > 0) {
      final unit = extent * OlympusHero._ruleWidth / 224;
      canvas
        ..save()
        ..translate(extent / 2, extent * OlympusHero._ruleTop)
        ..scale(unit * ruled, unit)
        ..translate(-112, 0)
        ..drawPath(
          _rule,
          Paint()
            ..color = OlympusColors.gold.withValues(alpha: ruled)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(OlympusHeroPainter oldDelegate) => true;
}
