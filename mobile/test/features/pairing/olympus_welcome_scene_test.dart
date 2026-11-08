import 'package:buzz/features/pairing/pairing_page.dart';
import 'package:buzz/shared/olympus/olympus_art.dart';
import 'package:buzz/shared/olympus/olympus_hero.dart';
import 'package:buzz/shared/olympus/olympus_scene_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/widget_helpers.dart';

void main() {
  testWidgets(
    'welcome sky drifts and strikes, pauses accessibly, and keeps actions',
    (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final reducedMotion = ValueNotifier(false);
      addTearDown(reducedMotion.dispose);
      var communityLinks = 0;
      await tester.pumpWidget(
        WidgetHelpers.testable(
          child: ValueListenableBuilder<bool>(
            valueListenable: reducedMotion,
            builder: (context, reduced, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: PairingPage(
                connectionLanding: true,
                onCommunityLink: () => communityLinks++,
              ),
            ),
          ),
        ),
      );
      Animation<double>? clock() =>
          (tester
                      .widget<CustomPaint>(
                        find.byKey(const Key('olympus-hero-mark')),
                      )
                      .painter!
                  as OlympusHeroPainter)
              .clock;

      expect(find.text('OLYMPUS'), findsOneWidget);
      expect(find.bySemanticsLabel('Olympus'), findsOneWidget);
      expect(
        find.text(
          'Your people, your agents, your projects —\nall in one place.',
        ),
        findsOneWidget,
      );
      final start = clock()!.value;
      var flashed = false;
      for (var frame = 0; frame < 130; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
        flashed |= OlympusMotion.flash(OlympusSceneClock.seconds(clock()!)) > 0;
      }
      expect(clock()!.value, greaterThan(start));
      expect(flashed, isTrue);
      await tester.tap(find.text('Enter a community link').hitTestable());
      expect(communityLinks, 1);

      reducedMotion.value = true;
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(clock(), isNull);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(find.text('Scan a QR code').hitTestable(), findsOneWidget);

      reducedMotion.value = false;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(clock(), isNull);
      expect(tester.binding.hasScheduledFrame, isFalse);

      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await tester.pump();
      final resumed = clock()!.value;
      await tester.pump(const Duration(milliseconds: 100));
      expect(clock()!.value, greaterThan(resumed));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final paused = clock()!.value;
      await tester.pump(const Duration(seconds: 1));
      expect(clock()!.value, paused);
      expect(tester.binding.hasScheduledFrame, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(clock()!.value, greaterThan(paused));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
