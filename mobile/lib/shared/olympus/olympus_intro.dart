import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'olympus_art.dart';
import 'olympus_scene_clock.dart';

class OlympusIntro extends HookWidget {
  const OlympusIntro({
    super.key,
    required this.delay,
    required this.duration,
    required this.child,
  });

  final double delay;
  final double duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scene = OlympusSceneClock.of(context);
    final clock = scene == null || scene.reduced ? null : scene.clock;
    final shown = useListenableSelector(
      clock,
      () => clock == null
          ? 1.0
          : OlympusMotion.span(
              OlympusSceneClock.seconds(clock),
              delay,
              duration,
            ),
    );
    return Opacity(
      opacity: shown,
      alwaysIncludeSemantics: true,
      child: Transform.translate(
        offset: Offset(0, 8 * (1 - shown)),
        child: child,
      ),
    );
  }
}
