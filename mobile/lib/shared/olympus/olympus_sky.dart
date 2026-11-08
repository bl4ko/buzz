import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'olympus_art.dart';
import 'use_olympus_reduced_motion.dart';
import 'olympus_colors.dart';
import 'olympus_scene_clock.dart';

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
    final reducedMotion = useOlympusReducedMotion(context);
    final lifecycle = useAppLifecycleState();
    final progress = useValueListenable(scannerProgress);
    final controller = useAnimationController(duration: OlympusMotion.cycle);
    final moving = animated && !reducedMotion;
    final playing =
        moving &&
        progress < 1 &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
    useEffect(() {
      playing ? controller.repeat() : controller.stop();
      return null;
    }, [controller, playing]);
    final clock = moving ? controller : null;
    return OlympusSceneClock(
      clock: clock,
      child: ColoredBox(
        key: const Key('olympus-sky'),
        color: OlympusColors.navy,
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: ExcludeSemantics(
                child: Opacity(
                  key: const Key('scanner-scene-opacity'),
                  opacity: 1 - progress,
                  child: Transform.scale(
                    key: const Key('scanner-scene-scale'),
                    scale: reducedMotion ? 1 : 1 - 0.04 * progress,
                    child: RepaintBoundary(
                      child: CustomPaint(painter: _SkyPainter(clock)),
                    ),
                  ),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.clock) : super(repaint: clock);

  final Animation<double>? clock;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final clock = this.clock;
    final seconds = clock == null ? null : OlympusSceneClock.seconds(clock);
    double drift(double period, double offset) =>
        seconds == null ? 0 : OlympusMotion.drift(seconds + offset, period);
    final unit = size.width / 290;
    OlympusArt.paintBackCloud(
      canvas,
      Offset(size.width * 0.22 + drift(22, 0) * 40 * unit, size.height * 0.17),
      unit * 0.5,
      opacity: 0.3,
    );
    OlympusArt.paintBackCloud(
      canvas,
      Offset(size.width * 0.8 - drift(18, 7) * 30 * unit, size.height * 0.25),
      unit * 0.36,
      opacity: 0.22,
    );
    final flash = seconds == null ? 0.0 : OlympusMotion.flash(seconds);
    if (flash > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: flash),
      );
    }
  }

  @override
  bool shouldRepaint(_SkyPainter oldDelegate) => clock != oldDelegate.clock;
}
