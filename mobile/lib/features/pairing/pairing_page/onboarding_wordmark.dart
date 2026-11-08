import 'package:flutter/material.dart';

import '../../../shared/olympus/olympus_hero.dart';

class OnboardingWordmark extends StatelessWidget {
  const OnboardingWordmark({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Olympus',
    image: true,
    child: const ExcludeSemantics(
      child: Stack(
        children: [
          // Keeps the welcome layout's intrinsic height of the former artwork.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 96),
              AspectRatio(aspectRatio: 777 / 326),
            ],
          ),
          Positioned.fill(child: OlympusHero()),
        ],
      ),
    ),
  );
}
