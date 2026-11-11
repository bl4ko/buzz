import 'dart:typed_data';

import 'package:buzz/features/pairing/pairing_page.dart';
import 'package:buzz/shared/olympus/olympus_art.dart';
import 'package:buzz/shared/olympus/olympus_hero.dart';
import 'package:buzz/shared/olympus/olympus_scene_clock.dart';
import 'package:buzz/shared/olympus/olympus_splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/widget_helpers.dart';

void main() {
  testWidgets(
    'welcome scene flashes, keeps a halo pulse for Reduce Motion, stops '
    'without animations, and keeps actions',
    (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final still = ValueNotifier(false);
      addTearDown(still.dispose);
      var communityLinks = 0;
      await tester.pumpWidget(
        WidgetHelpers.testable(
          child: ValueListenableBuilder<bool>(
            valueListenable: still,
            builder: (context, disabled, _) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: disabled),
              child: PairingPage(
                connectionLanding: true,
                onCommunityLink: () => communityLinks++,
              ),
            ),
          ),
        ),
      );
      OlympusHeroPainter painter() =>
          tester
                  .widget<CustomPaint>(
                    find
                        .descendant(
                          of: find.byType(OlympusHero),
                          matching: find.byType(CustomPaint),
                        )
                        .first,
                  )
                  .painter!
              as OlympusHeroPainter;
      Animation<double>? clock() => painter().clock;

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
        flashed |=
            OlympusMotion.frames(
              OlympusMotion.since(OlympusSceneClock.seconds(clock()!), 1.7, 21),
              OlympusMotion.flash,
            ) >
            0;
      }
      expect(clock()!.value, greaterThan(start));
      expect(flashed, isTrue);
      await tester.tap(find.text('Enter a community link').hitTestable());
      expect(communityLinks, 1);

      still.value = true;
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(clock(), isNull);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(find.text('Scan a QR code').hitTestable(), findsOneWidget);

      still.value = false;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      await tester.pump();
      expect(painter().reduced, isTrue);
      final reduced = clock()!.value;
      await tester.pump(const Duration(milliseconds: 100));
      expect(clock()!.value, greaterThan(reduced));

      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await tester.pump();
      expect(painter().reduced, isFalse);
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

  testWidgets('first welcome frame matches the splash', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const frameKey = Key('frame');
    Future<Uint8List> frame(Widget child) async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: frameKey,
          child: WidgetHelpers.testable(child: child),
        ),
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(frameKey),
      );
      late Uint8List pixels;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData();
        image.dispose();
        pixels = data!.buffer.asUint8List();
      });
      return pixels;
    }

    final splash = await frame(const OlympusSplash(semanticLabel: 'Starting'));
    final welcome = await frame(const PairingPage(connectionLanding: true));
    var difference = 0;
    for (var index = 0; index < splash.length; index++) {
      difference += (splash[index] - welcome[index]).abs();
    }
    expect(difference / splash.length, lessThan(0.5));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('welcome content arrives after the launch mark hand-over', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      WidgetHelpers.testable(child: const PairingPage(connectionLanding: true)),
    );
    double opacity(String text) => tester
        .widget<Opacity>(
          find
              .ancestor(of: find.text(text), matching: find.byType(Opacity))
              .first,
        )
        .opacity;
    const tagline =
        'Your people, your agents, your projects —\nall in one place.';
    expect(opacity(tagline), 0);
    expect(opacity('Scan a QR code'), 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2200));
    expect(opacity(tagline), 1);
    expect(opacity('Scan a QR code'), 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in const [Size(320, 568), Size(375, 667)]) {
    testWidgets('welcome hero keeps actions on a ${size.width}x${size.height} '
        'screen', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        WidgetHelpers.testable(child: const PairingPage()),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final hero = tester.getRect(find.byType(OlympusHero));
      expect(hero.width, closeTo(size.height * 0.3, 0.5));
      expect(hero.height, greaterThanOrEqualTo(OlympusHero.minExtent));
      expect(hero.center.dx, closeTo(size.width / 2, 0.5));
      expect(
        hero.bottom,
        lessThan(tester.getRect(find.text('Scan a QR code')).top),
      );
      for (final label in ['Scan a QR code', 'Use pairing code']) {
        expect(find.text(label).hitTestable(), findsOneWidget);
        expect(tester.getRect(find.text(label)).bottom, lessThan(size.height));
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
