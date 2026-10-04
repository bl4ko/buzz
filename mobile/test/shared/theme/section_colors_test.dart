import 'package:buzz/shared/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Storm section colors follow names and preserve other themes', (
    tester,
  ) async {
    final storm = AppTheme.dark(themeName: 'tokyo-night-storm');
    final colors = <String, Color>{};
    Future<void> render(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              for (final name in ['Unreads', 'Agents', 'Alerts', 'Channels']) {
                colors[name] = navigationSectionForeground(
                  context,
                  label: name,
                );
                expect(
                  colors[name],
                  navigationSectionForeground(
                    context,
                    label: ' ${name.toUpperCase()} ',
                  ),
                );
              }
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await render(storm);
    expect(colors.values.toList(), const [
      Color(0xFF7DCFFF),
      Color(0xFFB4F9F8),
      Color(0xFFE0AF68),
      Color(0xFF7AA2F7),
    ]);
    await render(AppTheme.dark());
    expect(colors.values.toSet().length, 1);
  });
}
