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
          home: Builder(
            builder: (context) {
              final color = navigationSectionForeground(context);
              if (theme.extension<AppColors>()?.sectionForeground != null) {
                expect(color, const Color(0xFF7AA2F7));
                expect(color, isNot(navigationPrimaryForeground(context)));
              } else {
                expect(
                  color,
                  navigationPrimaryForeground(context).withValues(alpha: 0.8),
                );
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
