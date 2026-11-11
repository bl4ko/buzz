import 'package:flutter/material.dart';

import '../olympus/olympus_bolt_spinner.dart';
import '../theme/theme.dart';

/// The full-page loading mark: the Olympus comet ring around the bolt.
class BeeLoadingMark extends StatelessWidget {
  const BeeLoadingMark({super.key});

  static const _width = 80.0;
  static const _height = _width * 309 / 466;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    liveRegion: true,
    child: ExcludeSemantics(
      child: SizedBox(
        width: _width,
        height: _height,
        child: Center(
          child: OlympusBoltSpinner(
            size: _height,
            light: context.colors.brightness == Brightness.light,
          ),
        ),
      ),
    ),
  );
}
