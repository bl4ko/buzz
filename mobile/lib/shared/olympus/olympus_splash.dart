import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'olympus_art.dart';
import 'olympus_colors.dart';

class OlympusSplash extends StatelessWidget {
  const OlympusSplash({super.key, required this.semanticLabel});

  final String semanticLabel;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
    ),
    child: ColoredBox(
      key: const Key('olympus-splash'),
      color: OlympusColors.navy,
      child: Center(
        child: Semantics(
          liveRegion: true,
          label: semanticLabel,
          child: const RepaintBoundary(
            child: CustomPaint(
              size: Size.square(OlympusArt.launchExtent),
              painter: OlympusMarkPainter(),
            ),
          ),
        ),
      ),
    ),
  );
}

class OlympusMarkPainter extends CustomPainter {
  const OlympusMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    OlympusArt.fit(canvas, OlympusArt.markView, size);
    OlympusArt.paintMedallion(canvas, null);
  }

  @override
  bool shouldRepaint(OlympusMarkPainter oldDelegate) => false;
}
