import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'olympus_art.dart';
import 'olympus_bolt_spinner.dart';
import 'olympus_colors.dart';

class OlympusSplash extends StatelessWidget {
  const OlympusSplash({super.key, required this.semanticLabel});

  static const markExtent = 168.0;

  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    const view = OlympusArt.markViewBox;
    const scale = markExtent / 1056;
    final bolt = Rect.fromLTRB(
      (OlympusArt.boltBounds.left - view.left) * scale,
      (OlympusArt.boltBounds.top - view.top) * scale,
      (OlympusArt.boltBounds.right - view.left) * scale,
      (OlympusArt.boltBounds.bottom - view.top) * scale,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
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
            child: ExcludeSemantics(
              child: SizedBox.square(
                dimension: markExtent,
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: CustomPaint(painter: _MountainPainter()),
                    ),
                    Positioned(
                      left: bolt.center.dx - bolt.height / 2,
                      top: bolt.top,
                      child: OlympusBoltSpinner(
                        size: bolt.height,
                        color: OlympusColors.gold,
                        startCharged: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MountainPainter extends CustomPainter {
  const _MountainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const view = OlympusArt.markViewBox;
    final scale = size.width / view.width;
    canvas
      ..save()
      ..scale(scale)
      ..translate(-view.left, -view.top);
    OlympusArt.paintMountain(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MountainPainter oldDelegate) => false;
}
