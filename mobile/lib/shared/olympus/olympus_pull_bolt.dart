import 'package:flutter/material.dart';

import 'olympus_bolt_spinner.dart';

class OlympusPullBolt extends StatelessWidget {
  const OlympusPullBolt({
    super.key,
    required this.height,
    required this.color,
    required this.charge,
    required this.loading,
  });

  final double height;
  final Color color;
  final double charge;
  final bool loading;

  @override
  Widget build(BuildContext context) => Center(
    child: loading
        ? OlympusBoltSpinner(size: height, color: color, startCharged: true)
        : CustomPaint(
            size: Size.square(height),
            painter: OlympusBoltPainter(
              progress: AlwaysStoppedAnimation(charge.clamp(0.0, 1.0) * 0.7),
              color: color,
            ),
          ),
  );
}
