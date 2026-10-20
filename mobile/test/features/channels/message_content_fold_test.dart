import 'package:buzz/features/channels/message_content.dart';
import 'package:buzz/shared/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _bodyStyle = TextStyle(fontSize: 15, height: 20 / 15);
const _foldHeight = 20.0 * messageFoldLines;

Widget _testable(Widget child, {ProviderContainer? container}) {
  final app = MaterialApp(
    theme: AppTheme.light(),
    builder: (context, child) => AppMarkdownTheme(child: child!),
    home: Scaffold(
      body: SingleChildScrollView(child: SizedBox(width: 320, child: child)),
    ),
  );
  return container == null
      ? ProviderScope(child: app)
      : UncontrolledProviderScope(container: container, child: app);
}

String _paragraphs(int count) => List.generate(
  count,
  (index) => 'Paragraph ${index + 1} of a long agent reply.',
).join('\n\n');

Future<void> _pumpContent(
  WidgetTester tester,
  String content, {
  bool foldExpanded = false,
  ProviderContainer? container,
}) async {
  await tester.pumpWidget(
    _testable(
      container: container,
      MessageContent(
        key: const ValueKey('content'),
        content: content,
        baseStyle: _bodyStyle,
        foldId: 'message-1',
        foldExpanded: foldExpanded,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 16));
}

double _contentHeight(WidgetTester tester) =>
    tester.getSize(find.byKey(const ValueKey('content'))).height;

final _toggle = find.byKey(const ValueKey('message-fold-toggle'));

void main() {
  testWidgets('a short message has no fold control', (tester) async {
    await _pumpContent(tester, 'A short reply.');

    expect(_toggle, findsNothing);
    expect(_contentHeight(tester), lessThan(_foldHeight));
  });

  testWidgets('a long message folds and toggles in place', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpContent(tester, _paragraphs(30));

    expect(find.text('Show more'), findsOneWidget);
    expect(
      tester.getSemantics(_toggle),
      isSemantics(label: 'Show more', isButton: true, hasTapAction: true),
    );
    final foldedHeight = _contentHeight(tester);
    expect(foldedHeight, lessThan(_foldHeight + 60));

    await tester.ensureVisible(_toggle);
    await tester.tap(_toggle);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('Show less'), findsOneWidget);
    expect(_contentHeight(tester), greaterThan(foldedHeight * 2));

    await tester.ensureVisible(_toggle);
    await tester.tap(_toggle);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('Show more'), findsOneWidget);
    expect(_contentHeight(tester), foldedHeight);
    semantics.dispose();
  });

  testWidgets('a highlighted message starts expanded', (tester) async {
    await _pumpContent(tester, _paragraphs(30), foldExpanded: true);

    expect(find.text('Show less'), findsOneWidget);
    expect(_contentHeight(tester), greaterThan(_foldHeight * 2));
  });

  testWidgets('an emoji-only message never folds', (tester) async {
    await tester.pumpWidget(
      _testable(
        const MessageContent(
          content: '🎉',
          baseStyle: _bodyStyle,
          foldId: 'message-1',
          scaleEmojiOnly: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(_toggle, findsNothing);
  });

  testWidgets('an expanded message stays expanded after it remounts', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpContent(tester, _paragraphs(30), container: container);
    await tester.ensureVisible(_toggle);
    await tester.tap(_toggle);
    await tester.pump(const Duration(milliseconds: 16));

    await tester.pumpWidget(
      _testable(container: container, const SizedBox.shrink()),
    );
    await _pumpContent(tester, _paragraphs(30), container: container);

    expect(find.text('Show less'), findsOneWidget);
    expect(_contentHeight(tester), greaterThan(_foldHeight * 2));
  });
}
