import 'package:flutter/material.dart';

import '../theme/theme.dart';

abstract final class OlympusColors {
  static const navy = Color(0xFF0E1630);
  static const navyRaised = Color(0xFF17224A);
  static const navyHigh = Color(0xFF202D5C);
  static const ridge = Color(0xFF303C8C);
  static const marble = Color(0xFFF5EBD0);
  static const gold = Color(0xFFF7C234);
  static const goldHot = Color(0xFFFFF6C8);
  static const goldInk = Color(0xFFB8730F);
  static const goldInkHot = Color(0xFFE9A81C);
  static const glow = Color(0xFFFFAE1A);
  static const cloudShadow = Color(0xFF8FA3D9);
  static const star = Color(0xFFEEF2FF);
  static const white = Color(0xFFFFFFFF);
}

final ThemeData olympusOnboardingTheme = AppTheme.dark(
  colorScheme: darkColorScheme.copyWith(
    primary: OlympusColors.gold,
    onPrimary: OlympusColors.navy,
    primaryContainer: OlympusColors.navyHigh,
    onPrimaryContainer: OlympusColors.marble,
    secondary: OlympusColors.cloudShadow,
    onSecondary: OlympusColors.navy,
    secondaryContainer: OlympusColors.navyHigh,
    onSecondaryContainer: OlympusColors.marble,
    surface: OlympusColors.navy,
    onSurface: OlympusColors.marble,
    onSurfaceVariant: OlympusColors.cloudShadow,
    outline: OlympusColors.ridge,
    outlineVariant: OlympusColors.navyHigh,
    inverseSurface: OlympusColors.marble,
    onInverseSurface: OlympusColors.navy,
    surfaceContainerLowest: OlympusColors.navy,
    surfaceContainerLow: OlympusColors.navyRaised,
    surfaceContainer: OlympusColors.navyRaised,
    surfaceContainerHigh: OlympusColors.navyHigh,
    surfaceContainerHighest: OlympusColors.navyHigh,
  ),
);
