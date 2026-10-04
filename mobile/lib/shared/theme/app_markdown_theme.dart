import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import 'app_theme.dart';
import 'app_colors.dart';
import 'code_style.dart';

class AppMarkdownTheme extends StatelessWidget {
  const AppMarkdownTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = Theme.of(context).extension<AppColors>();
    final ambient = GptMarkdownTheme.of(context);
    return GptMarkdownTheme(
      gptThemeData: ambient.copyWith(
        h1: ambient.h1?.copyWith(color: colors?.messageHeading),
        h2: ambient.h2?.copyWith(color: colors?.messageHeading),
        h3: ambient.h3?.copyWith(color: colors?.messageHeading),
        h4: ambient.h4?.copyWith(color: colors?.messageHeading),
        h5: ambient.h5?.copyWith(color: colors?.messageHeading),
        h6: ambient.h6?.copyWith(color: colors?.messageHeading),
        linkColor: colors?.messageLink,
        linkHoverColor: colors?.messageLink,
        // Inline code is otherwise drawn in gpt_markdown's own bundled face, at
        // its own size, tinted from `onSurface`. Stating the app's code style
        // gives every Markdown surface the face, size and chip colours a fenced
        // code block already uses.
        inlineCode: InlineCodeStyle(
          fontFamily: CodeStyle.fontFamily,
          fontSizeFactor: CodeStyle.fontSizeFactor,
          color: colors?.messageCode ?? scheme.onSurface,
          backgroundColor: CodeStyle.background(scheme),
          borderColor: CodeStyle.border(scheme),
          // A chip is small, so it takes the smallest step of the app's radius
          // scale rather than the `Radii.card` a block uses.
          borderRadius: const Radius.circular(Radii.xs),
        ).resolve(scheme),
      ),
      child: child,
    );
  }
}
