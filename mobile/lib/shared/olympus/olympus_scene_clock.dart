import 'package:flutter/widgets.dart';

import 'olympus_art.dart';

class OlympusSceneClock extends InheritedWidget {
  const OlympusSceneClock({
    super.key,
    required this.clock,
    required super.child,
  });

  final Animation<double>? clock;

  static Animation<double>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OlympusSceneClock>()?.clock;

  static double seconds(Animation<double> clock) =>
      clock.value * OlympusMotion.cycle.inSeconds;

  @override
  bool updateShouldNotify(OlympusSceneClock oldWidget) =>
      clock != oldWidget.clock;
}
