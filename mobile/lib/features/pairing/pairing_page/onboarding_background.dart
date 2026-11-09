part of '../pairing_page.dart';

class _OnboardingBackground extends StatelessWidget {
  final Widget child;
  final bool websiteWelcome;
  final ValueListenable<double> scannerProgress;

  const _OnboardingBackground({
    required this.child,
    this.websiteWelcome = false,
    this.scannerProgress = const AlwaysStoppedAnimation(0),
  });

  @override
  Widget build(BuildContext context) => OlympusSky(
    key: const Key('pairing-onboarding-background'),
    animated: websiteWelcome,
    scannerProgress: scannerProgress,
    child: Theme(data: olympusOnboardingTheme, child: child),
  );
}
