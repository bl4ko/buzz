import 'package:flutter/material.dart';

import '../../../shared/olympus/olympus_hero.dart';

class OnboardingWordmark extends StatelessWidget {
  const OnboardingWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    final room =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    return Semantics(
      label: 'Olympus',
      image: true,
      child: ExcludeSemantics(
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: (room - 667).clamp(0.0, 96.0)),
                const AspectRatio(aspectRatio: 777 / 326),
              ],
            ),
            const Positioned.fill(child: OlympusHero()),
          ],
        ),
      ),
    );
  }
}
