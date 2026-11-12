import 'package:flutter/material.dart';

import '../olympus/olympus_key_loader.dart';
import '../olympus/olympus_inline_spinner.dart';
import '../theme/theme.dart';

/// Page-level loads use [page]; inline and frequent loads use [inline].
enum BuzzLoadingStyle { inline, page }

/// The smallest size that defaults to [BuzzLoadingStyle.page].
const double buzzLoadingPageMinSize = 40;

/// The shared mobile loading indicator.
class BuzzLoadingIndicator extends StatelessWidget {
  /// The spinner's square extent.
  final double size;

  /// The inline spinner color. The page loader keeps its gold and reads this
  /// only as the ink of its surface.
  final Color? color;

  /// The accessibility announcement for this loading state.
  final String semanticLabel;

  /// The spinner variant; defaults by [size] (see [buzzLoadingPageMinSize]).
  final BuzzLoadingStyle? style;

  /// Creates a looping loading indicator.
  const BuzzLoadingIndicator({
    this.size = 40,
    this.color,
    this.semanticLabel = 'Loading',
    this.style,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    const spinnerKey = ValueKey('buzz-loading-indicator-spinner');
    final color = this.color;
    return Semantics(
      liveRegion: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: switch (style ??
            (size >= buzzLoadingPageMinSize
                ? BuzzLoadingStyle.page
                : BuzzLoadingStyle.inline)) {
          BuzzLoadingStyle.page => OlympusKeyLoader(
            key: spinnerKey,
            size: size,
            light: color == null
                ? context.colors.brightness == Brightness.light
                : ThemeData.estimateBrightnessForColor(color) ==
                      Brightness.dark,
          ),
          BuzzLoadingStyle.inline => OlympusInlineSpinner(
            key: spinnerKey,
            size: size,
            color: color ?? context.colors.onSurfaceVariant,
          ),
        },
      ),
    );
  }
}
