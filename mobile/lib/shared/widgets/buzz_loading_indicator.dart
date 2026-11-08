import 'package:flutter/material.dart';

import '../olympus/olympus_bolt_spinner.dart';
import '../olympus/olympus_cloud_spinner.dart';
import '../olympus/olympus_colors.dart';
import '../theme/theme.dart';

/// Page-level loads use [bolt]; inline and frequent loads use [clouds].
enum BuzzLoadingStyle { clouds, bolt }

/// The shared mobile loading indicator.
class BuzzLoadingIndicator extends StatelessWidget {
  /// The spinner's square extent.
  final double size;

  /// An optional spinner color. Defaults to gold for [BuzzLoadingStyle.bolt]
  /// and the theme's muted foreground for [BuzzLoadingStyle.clouds].
  final Color? color;

  /// The accessibility announcement for this loading state.
  final String semanticLabel;

  /// The spinner variant.
  final BuzzLoadingStyle style;

  /// Creates a looping loading indicator.
  const BuzzLoadingIndicator({
    this.size = 40,
    this.color,
    this.semanticLabel = 'Loading',
    this.style = BuzzLoadingStyle.clouds,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    const spinnerKey = ValueKey('buzz-loading-indicator-spinner');
    return Semantics(
      liveRegion: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: switch (style) {
          BuzzLoadingStyle.bolt => OlympusBoltSpinner(
            key: spinnerKey,
            size: size,
            color: color ?? OlympusColors.gold,
          ),
          BuzzLoadingStyle.clouds => OlympusCloudSpinner(
            key: spinnerKey,
            size: size,
            color: color ?? context.colors.onSurfaceVariant,
          ),
        },
      ),
    );
  }
}
