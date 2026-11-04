import 'package:flutter/material.dart';

import 'adaptive_theme.dart';
import 'chat_colors.dart';
import 'color_scheme.dart';
import 'app_theme.dart';
import 'theme_catalog.dart';

/// The separate dark Tokyo Night Storm theme.
const stormThemeName = 'tokyo-night-storm';

/// Chat-only colors, independent of controls and navigation.
@immutable
class ChatColors extends ThemeExtension<ChatColors> {
  /// Creates the outgoing message palette.
  const ChatColors({required this.outgoing, required this.foreground});

  /// Fill for messages authored by the active signing identity.
  final Color outgoing;

  /// Desktop text color paired with the outgoing fill.
  final Color foreground;

  /// Reads chat colors while supporting isolated widget previews.
  static ChatColors of(BuildContext context) =>
      Theme.of(context).extension<ChatColors>() ??
      ChatColors(
        outgoing: Theme.of(context).colorScheme.primary,
        foreground: contrastForeground(Theme.of(context).colorScheme.primary),
      );

  @override
  ChatColors copyWith({Color? outgoing, Color? foreground}) => ChatColors(
    outgoing: outgoing ?? this.outgoing,
    foreground: foreground ?? this.foreground,
  );

  @override
  ChatColors lerp(covariant ChatColors? other, double t) => other == null
      ? this
      : ChatColors(
          outgoing: Color.lerp(outgoing, other.outgoing, t)!,
          foreground: Color.lerp(foreground, other.foreground, t)!,
        );
}

/// Builds the single mobile palette. Legacy theme names remain readable for
/// community preference compatibility, but never select an application palette.
ThemeData mobileAppearanceTheme(
  Brightness brightness,
  String chatColor, {
  String? theme,
}) {
  final storm = brightness == Brightness.dark && theme == stormThemeName
      ? findTheme(stormThemeName)
      : null;
  final base = storm != null
      ? AppTheme.dark(
          colorScheme: generateColorScheme(storm),
          themeName: stormThemeName,
        )
      : brightness == Brightness.dark
      ? AppTheme.dark()
      : AppTheme.light();
  final index = chatColorIndex(chatColor);
  return base.copyWith(
    extensions: [
      ...base.extensions.values,
      ChatColors(
        outgoing: chatColorForScheme(base.colorScheme, index),
        foreground: chatForegroundForScheme(base.colorScheme, index),
      ),
    ],
  );
}
