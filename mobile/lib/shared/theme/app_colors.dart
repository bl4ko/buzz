import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color success;
  final Color warning;
  final Color accent;
  final Color huddleDrawerSurface;
  final Color huddleControlSurface;
  final Color onHuddleDrawer;
  final Color? messageHeading;
  final Color? messageStrong;
  final Color? messageCode;
  final Color? messageLink;
  final Color? messageAuthor;
  final List<Color>? sectionColors;

  /// Gradient for the app's top section, non-null only under the Buzz themes.
  /// Carried on the theme rather than read from a provider so any surface can
  /// opt in via `context.appColors.topSectionGradient` — see
  /// `buzzTopSectionGradient`.
  final Gradient? topSectionGradient;

  const AppColors({
    required this.success,
    required this.warning,
    required this.accent,
    required this.huddleDrawerSurface,
    required this.huddleControlSurface,
    required this.onHuddleDrawer,
    this.topSectionGradient,
    this.messageHeading,
    this.messageStrong,
    this.messageCode,
    this.messageLink,
    this.messageAuthor,
    this.sectionColors,
  });

  @override
  AppColors copyWith({
    Color? success,
    Color? warning,
    Color? accent,
    Color? huddleDrawerSurface,
    Color? huddleControlSurface,
    Color? onHuddleDrawer,
    Gradient? topSectionGradient,
    Color? messageHeading,
    Color? messageStrong,
    Color? messageCode,
    Color? messageLink,
    Color? messageAuthor,
    List<Color>? sectionColors,
  }) => AppColors(
    success: success ?? this.success,
    warning: warning ?? this.warning,
    accent: accent ?? this.accent,
    huddleDrawerSurface: huddleDrawerSurface ?? this.huddleDrawerSurface,
    huddleControlSurface: huddleControlSurface ?? this.huddleControlSurface,
    onHuddleDrawer: onHuddleDrawer ?? this.onHuddleDrawer,
    topSectionGradient: topSectionGradient ?? this.topSectionGradient,
    messageHeading: messageHeading ?? this.messageHeading,
    messageStrong: messageStrong ?? this.messageStrong,
    messageCode: messageCode ?? this.messageCode,
    messageLink: messageLink ?? this.messageLink,
    messageAuthor: messageAuthor ?? this.messageAuthor,
    sectionColors: sectionColors ?? this.sectionColors,
  );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      huddleDrawerSurface: Color.lerp(
        huddleDrawerSurface,
        other.huddleDrawerSurface,
        t,
      )!,
      huddleControlSurface: Color.lerp(
        huddleControlSurface,
        other.huddleControlSurface,
        t,
      )!,
      onHuddleDrawer: Color.lerp(onHuddleDrawer, other.onHuddleDrawer, t)!,
      topSectionGradient: Gradient.lerp(
        topSectionGradient,
        other.topSectionGradient,
        t,
      ),
      messageHeading: Color.lerp(messageHeading, other.messageHeading, t),
      messageStrong: Color.lerp(messageStrong, other.messageStrong, t),
      messageCode: Color.lerp(messageCode, other.messageCode, t),
      messageLink: Color.lerp(messageLink, other.messageLink, t),
      messageAuthor: Color.lerp(messageAuthor, other.messageAuthor, t),
      sectionColors: sectionColors == null || other.sectionColors == null
          ? (t < 0.5 ? sectionColors : other.sectionColors)
          : List.generate(
              sectionColors!.length,
              (index) => Color.lerp(
                sectionColors![index],
                other.sectionColors![index],
                t,
              )!,
            ),
    );
  }
}
