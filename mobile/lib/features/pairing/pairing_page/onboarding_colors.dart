part of '../pairing_page.dart';

// Foregrounds for the fixed Buzz shell artwork, independent of accent choice.
extension _OnboardingColors on BuildContext {
  bool get _onboardingIsDark => Theme.of(this).brightness == Brightness.dark;
  Color get _onboardingInk =>
      _onboardingIsDark ? OlympusColors.marble : const Color(0xFF111111);
  Color get _onboardingMutedInk =>
      _onboardingIsDark ? OlympusColors.cloudShadow : const Color(0xB3111111);
  Color get _onboardingCtaLabel =>
      _onboardingIsDark ? OlympusColors.navy : Colors.white;
  Color get _onboardingCta =>
      _onboardingIsDark ? OlympusColors.gold : _onboardingInk;
  Color get _onboardingErrorInk => colors.error;
  Color get _onboardingInputSurface => _onboardingIsDark
      ? OlympusColors.navyRaised
      : Colors.white.withValues(alpha: 0.7);

  OutlineInputBorder get _inputBorder => OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radii.md),
    borderSide: BorderSide(color: _onboardingInk.withValues(alpha: 0.18)),
  );

  ButtonStyle get _onboardingButtonStyle => FilledButton.styleFrom(
    minimumSize: const Size(0, 52),
    padding: const EdgeInsets.symmetric(
      horizontal: Grid.lg,
      vertical: Grid.twelve,
    ),
    backgroundColor: _onboardingCta,
    foregroundColor: _onboardingCtaLabel,
    disabledBackgroundColor: _onboardingCta.withValues(alpha: 0.38),
    disabledForegroundColor: _onboardingCtaLabel.withValues(alpha: 0.7),
    shape: const StadiumBorder(),
  );

  ButtonStyle get _onboardingSecondaryButtonStyle => TextButton.styleFrom(
    minimumSize: const Size(0, 52),
    padding: const EdgeInsets.symmetric(
      horizontal: Grid.md,
      vertical: Grid.xxs,
    ),
    backgroundColor: _onboardingInk.withValues(alpha: 0.1),
    foregroundColor: _onboardingInk,
    disabledBackgroundColor: _onboardingInk.withValues(alpha: 0.05),
    disabledForegroundColor: _onboardingInk.withValues(alpha: 0.45),
    shape: const StadiumBorder(),
  );
}
