import 'package:buzz/shared/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Storm uses one section color distinct from channel text', (
    tester,
  ) async {
    for (final theme in [
      AppTheme.dark(themeName: 'tokyo-night-storm'),
      AppTheme.dark(),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          themeAnimationDuration: Duration.zero,
          home: Builder(
            builder: (context) {
              const storm = Color(0xFF7AA2F7);
              final hasSectionRole =
                  theme.extension<AppColors>()?.sectionForeground != null;
              for (final color in [
                navigationSectionForeground(context),
                navigationHeadingForeground(context),
              ]) {
                expect(color, hasSectionRole ? storm : isNot(storm));
              }
              if (hasSectionRole) {
                expect(storm, isNot(navigationPrimaryForeground(context)));
              }
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }
  });
}
