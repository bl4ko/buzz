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
  required BuzzLoadingStyle style,
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
}
