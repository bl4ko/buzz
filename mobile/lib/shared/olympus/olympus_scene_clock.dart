import 'package:flutter/widgets.dart';

import 'olympus_art.dart';

class OlympusSceneClock extends InheritedWidget {
  const OlympusSceneClock({
    super.key,
    required this.clock,
    required this.reduced,
    required this.hero,
    required super.child,
  });

  final Animation<double>? clock;
  final bool reduced;
  final GlobalKey hero;

  static OlympusSceneClock? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OlympusSceneClock>();

  static double seconds(Animation<double> clock) =>
      clock.value * OlympusMotion.cycle.inSeconds;

  @override
  bool updateShouldNotify(OlympusSceneClock oldWidget) =>
      clock != oldWidget.clock ||
      reduced != oldWidget.reduced ||
      hero != oldWidget.hero;
}
