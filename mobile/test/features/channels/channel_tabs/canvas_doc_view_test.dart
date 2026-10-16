import 'package:buzz/features/channels/channel_tabs/canvas_doc_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
