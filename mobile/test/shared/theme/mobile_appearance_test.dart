import 'package:buzz/shared/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop surface and text roles match in both modes', () {
    final light = mobileAppearanceTheme(Brightness.light, 'neutral');
    final dark = mobileAppearanceTheme(Brightness.dark, 'neutral');
    expect(light.colorScheme.surface, const Color(0xFFFFFFFF));
    expect(light.colorScheme.onSurface, const Color(0xFF0A0A0A));
    expect(light.colorScheme.onSurfaceVariant, const Color(0xFF646464));
    expect(light.colorScheme.outline, const Color(0xFFE8E8E8));
    expect(dark.colorScheme.surface, const Color(0xFF000000));
    expect(dark.colorScheme.onSurface, const Color(0xFFFFFFFF));
    expect(dark.colorScheme.onSurfaceVariant, const Color(0xFFC7C7C7));
    expect(dark.colorScheme.outline, const Color(0xFF1A1A1A));
  });

  for (final brightness in Brightness.values) {
    test('chat colors do not recolor controls in $brightness', () {
      final base = mobileAppearanceTheme(brightness, 'neutral');
      for (final accent in accentColors) {
        final theme = mobileAppearanceTheme(brightness, accent.wireValue);
        expect(theme.colorScheme, base.colorScheme);
        final fill = theme.extension<ChatColors>()!.outgoing;
        final foreground = theme.extension<ChatColors>()!.foreground;
        final a = fill.computeLuminance();
        final b = foreground.computeLuminance();
        final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
        expect(ratio, greaterThanOrEqualTo(4.5));
      }
    });
  }

  test('Storm message surfaces and roles come from its palette', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance();
      final y = b.computeLuminance();
      return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
    }

    final storm = mobileAppearanceTheme(
      Brightness.dark,
      'neutral',
      theme: stormThemeName,
    );
    final scheme = storm.colorScheme;
    final colors = storm.extension<AppColors>()!;
    final bubble = receivedMessageSurface(storm);
    expect(bubble, scheme.surfaceContainerHigh);
    expect(colors.tertiaryText, scheme.onSurfaceVariant);
    expect(colors.controlSurface, scheme.surfaceContainerHighest);
    for (final surface in [bubble, colors.controlSurface!]) {
      expect(surface.b, greaterThan(surface.r), reason: '$surface');
    }
    for (final ink in [
      scheme.onSurface,
      colors.messageLink!,
      colors.messageCode!,
      colors.messageStrong!,
    ]) {
      expect(contrast(ink, bubble), greaterThanOrEqualTo(4.5), reason: '$ink');
    }
    for (final ink in [colors.messageAuthor!, colors.tertiaryText!]) {
      expect(
        contrast(ink, scheme.surface),
        greaterThanOrEqualTo(4.5),
        reason: '$ink',
      );
    }
    final mentionFill = Color.alphaBlend(
      colors.messageLink!.withValues(alpha: 0.15),
      bubble,
    );
    expect(
      contrast(colors.messageLink!, mentionFill),
      greaterThanOrEqualTo(4.5),
    );

    for (final brightness in Brightness.values) {
      final theme = mobileAppearanceTheme(brightness, 'neutral');
      expect(
        receivedMessageSurface(theme),
        brightness == Brightness.dark
            ? const Color(0xFF292929)
            : const Color(0xFFF3F3F4),
      );
      expect(theme.extension<AppColors>()!.controlSurface, isNull);
    }
  });
}
