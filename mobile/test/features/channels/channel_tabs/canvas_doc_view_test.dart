import 'package:buzz/features/channels/channel_tabs/canvas_doc.dart';
import 'package:buzz/features/channels/channel_tabs/canvas_doc_provider.dart';
import 'package:buzz/features/channels/channel_tabs/canvas_doc_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _FixedCanvas extends CanvasDocNotifier {
  _FixedCanvas(super.key, this.version);

  final CanvasVersion version;

  @override
  CanvasVersion? build() => version;
}

void main() {
  Future<List<String>> pump(
    WidgetTester tester, {
    String draft = '# Notes',
    String? conflictAuthor,
  }) async {
    final log = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasEditorPane(
            draft: draft,
            onChanged: (_) {},
            conflictAuthor: conflictAuthor,
            saving: false,
            onSave: () => log.add('save'),
            onReload: () => log.add('reload'),
            onOverwrite: () => log.add('overwrite'),
            onCancel: () => log.add('cancel'),
          ),
        ),
      ),
    );
    return log;
  }

  testWidgets('conflict banner offers reload or overwrite and blocks save', (
    tester,
  ) async {
    final log = await pump(tester, conflictAuthor: 'Athene');
    expect(
      find.text('Changed by Athene. Reload or overwrite?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Save'));
    await tester.tap(find.text('Reload'));
    await tester.tap(find.text('Overwrite'));
    expect(log, ['reload', 'overwrite']);
  });

  testWidgets('oversize drafts cannot be saved', (tester) async {
    final log = await pump(tester, draft: 'x' * 65537);
    expect(find.textContaining('65537 / 65536'), findsOneWidget);
    await tester.tap(find.text('Save'));
    expect(log, isEmpty);
  });

  testWidgets('the canvas end scrolls above the bottom safe area', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    const key = ('c1', 'notes');
    final version = CanvasVersion(
      eventId: 'e' * 64,
      author: 'a' * 64,
      createdAt: 1,
      content: [for (var i = 0; i < 60; i++) 'Line $i'].join('\n\n'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          canvasDocProvider(key).overrideWith(() => _FixedCanvas(key, version)),
        ],
        child: const MaterialApp(
          home: Material(
            child: CanvasDocView(
              channelId: 'c1',
              canvasId: 'notes',
              canEdit: false,
            ),
          ),
        ),
      ),
    );
    await tester.fling(find.byType(ListView), const Offset(0, -20000), 5000);
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(find.byType(GptMarkdown)).dy,
      lessThanOrEqualTo(600 - 34),
    );
  });
}
