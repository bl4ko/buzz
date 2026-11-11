import 'package:flutter/material.dart';

import '../../../shared/olympus/olympus_hero.dart';

class OnboardingWordmark extends StatelessWidget {
  const OnboardingWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    final room =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    return OlympusHero(
      extent: (room * 0.3).clamp(OlympusHero.minExtent, 280.0),
    );
  }
}
