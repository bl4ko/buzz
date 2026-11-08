import 'package:flutter/material.dart';

import '../theme/theme.dart';

abstract final class OlympusColors {
  static const navy = Color(0xFF0E1630);
  static const mountain = Color(0xFF2E3F78);
  static const mountainShade = Color(0xFF3B4F92);
  static const marble = Color(0xFFF5EBD0);
  static const gold = Color(0xFFE8B931);
  static const cloudShadow = Color(0xFF8FA3D9);
  static const navyRaised = Color(0xFF17224A);
  static const navyHigh = Color(0xFF202D5C);
}

ThemeData olympusOnboardingTheme() => AppTheme.dark(
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
    outline: OlympusColors.mountain,
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
