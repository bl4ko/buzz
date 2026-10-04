part of '../message_content.dart';

class _ThemedBoldMd extends BoldMd {
  @override
  InlineSpan span(BuildContext context, String text, GptMarkdownConfig config) {
    final color = context.appColors.messageStrong;
    return super.span(
      context,
      text,
      color == null
          ? config
          : config.copyWith(
              style: (config.style ?? const TextStyle()).copyWith(color: color),
            ),
    );
  }
}
