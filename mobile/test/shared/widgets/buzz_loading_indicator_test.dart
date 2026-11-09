import 'package:buzz/shared/olympus/olympus_bolt_spinner.dart';
import 'package:buzz/shared/olympus/olympus_cloud_spinner.dart';
import 'package:buzz/shared/olympus/olympus_colors.dart';
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

  testWidgets('animates both Olympus spinners and holds still for reduced '
      'motion', (tester) async {
    final semantics = tester.ensureSemantics();
    for (final (style, brightness) in [
      (BuzzLoadingStyle.bolt, Brightness.light),
      (BuzzLoadingStyle.clouds, Brightness.light),
      (BuzzLoadingStyle.clouds, Brightness.dark),
    ]) {
      await tester.pumpWidget(
        _testable(
          disableAnimations: false,
          brightness: brightness,
          style: style,
        ),
      );
      await tester.pump(const Duration(milliseconds: 70));
      final painter = tester.widget<CustomPaint>(spinner).painter!;
      final (progress, color) = switch (painter) {
        OlympusBoltPainter(:final progress, :final color) => (progress, color),
        OlympusCloudPainter(:final progress, :final color) => (progress, color),
        _ => throw StateError('Unexpected painter $painter'),
      };
      expect(progress.value, greaterThan(0));
      expect(
        color,
        style == BuzzLoadingStyle.bolt
            ? OlympusColors.gold
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
      final still = tester.widget<CustomPaint>(spinner).painter!;
      expect(switch (still) {
        OlympusBoltPainter(:final color) => color,
        OlympusCloudPainter(:final color, :final still) when still => color,
        _ => null,
      }, Colors.white);
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
    semantics.dispose();
  });
  testWidgets('picks the bolt for page-size loads and clouds inline', (
    tester,
  ) async {
    for (final (size, painterType) in [
      (40.0, OlympusBoltPainter),
      (44.0, OlympusBoltPainter),
      (36.0, OlympusCloudPainter),
      (18.0, OlympusCloudPainter),
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
        style: BuzzLoadingStyle.bolt,
      ),
    );
    expect(
      tester.widget<CustomPaint>(spinner).painter,
      isA<OlympusBoltPainter>(),
    );
  });

  testWidgets('stops both spinners for the iOS Reduce Motion setting', (
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
      final progress = switch (tester.widget<CustomPaint>(spinner).painter) {
        OlympusBoltPainter(:final progress) => progress,
        OlympusCloudPainter(:final progress) => progress,
        final painter => throw StateError('Unexpected painter $painter'),
      };
      expect(progress.isAnimating, isFalse);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
