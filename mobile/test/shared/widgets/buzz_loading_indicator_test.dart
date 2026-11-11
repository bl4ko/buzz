import 'package:buzz/shared/olympus/olympus_key_loader.dart';
import 'package:buzz/shared/olympus/olympus_inline_spinner.dart';
import 'package:buzz/shared/theme/theme.dart';
import 'package:buzz/shared/widgets/buzz_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _testable({
  required bool disableAnimations,
  required Brightness brightness,
  BuzzLoadingStyle? style,
  double size = 40,
  Color? color,
}) {
  return MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
    home: MediaQuery(
      data: const MediaQueryData().copyWith(
        disableAnimations: disableAnimations,
      ),
      child: Scaffold(
        body: BuzzLoadingIndicator(
          semanticLabel: 'Loading photos',
          size: size,
          style: style,
          color: color,
        ),
      ),
    ),
  );
}

void main() {
  final spinner = find.descendant(
    of: find.byKey(const ValueKey('buzz-loading-indicator-spinner')),
    matching: find.byType(CustomPaint),
  );
  (Animation<double>, bool, Object) read(WidgetTester tester) =>
      switch (tester.widget<CustomPaint>(spinner).painter) {
        OlympusKeyPainter(:final progress, :final reduced, :final light) => (
          progress,
          reduced,
          light,
        ),
        OlympusInlinePainter(:final progress, :final reduced, :final color) => (
          progress,
          reduced,
          color,
        ),
        final painter => throw StateError('Unexpected painter $painter'),
      };

  testWidgets('animates both Olympus spinners and holds still without '
      'animations', (tester) async {
    final semantics = tester.ensureSemantics();
    for (final (style, brightness) in [
      (BuzzLoadingStyle.page, Brightness.light),
      (BuzzLoadingStyle.page, Brightness.dark),
      (BuzzLoadingStyle.inline, Brightness.light),
      (BuzzLoadingStyle.inline, Brightness.dark),
    ]) {
      await tester.pumpWidget(
        _testable(
          disableAnimations: false,
          brightness: brightness,
          style: style,
        ),
      );
      await tester.pump(const Duration(milliseconds: 70));
      final (progress, reduced, look) = read(tester);
      expect(progress.value, inExclusiveRange(0, 1));
      expect(reduced, isFalse);
      expect(
        look,
        style == BuzzLoadingStyle.page
            ? brightness == Brightness.light
            : tester.element(spinner).colors.onSurfaceVariant,
      );
      expect(tester.getSize(spinner), const Size.square(40));
      expect(find.bySemanticsLabel('Loading photos'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Loading photos')),
        isSemantics(isLiveRegion: true),
      );

      await tester.pumpWidget(
        _testable(
          disableAnimations: true,
          brightness: brightness,
          style: style,
          color: Colors.white,
        ),
      );
      await tester.pumpAndSettle();
      final (still, stillReduced, stillLook) = read(tester);
      expect(still.value, 1);
      expect(stillReduced, isTrue);
      expect(stillLook, style == BuzzLoadingStyle.page ? false : Colors.white);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    semantics.dispose();
  });

  testWidgets('picks the key loader for page-size loads and the tiles inline', (
    tester,
  ) async {
    for (final (size, painterType) in [
      (40.0, OlympusKeyPainter),
      (44.0, OlympusKeyPainter),
      (36.0, OlympusInlinePainter),
      (18.0, OlympusInlinePainter),
    ]) {
      await tester.pumpWidget(
        _testable(
          disableAnimations: false,
          brightness: Brightness.light,
          size: size,
        ),
      );
      expect(
        tester.widget<CustomPaint>(spinner).painter.runtimeType,
        painterType,
      );
    }
    await tester.pumpWidget(
      _testable(
        disableAnimations: false,
        brightness: Brightness.light,
        size: 18,
        style: BuzzLoadingStyle.page,
      ),
    );
    expect(
      tester.widget<CustomPaint>(spinner).painter,
      isA<OlympusKeyPainter>(),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pulses both spinners for the iOS Reduce Motion setting', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    for (final style in BuzzLoadingStyle.values) {
      await tester.pumpWidget(
        _testable(
          disableAnimations: false,
          brightness: Brightness.light,
          style: style,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final (progress, reduced, _) = read(tester);
      expect(reduced, isTrue);
      expect(progress.status, AnimationStatus.reverse);
      expect(progress.value, inExclusiveRange(0, 1));
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
