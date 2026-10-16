import 'package:buzz/features/channels/channel_tabs/search_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final athene = '3c'.padRight(64, '0');
  final members = [(pubkey: athene, displayName: 'Athene')];

  test('from: resolves to an author filter', () {
    final query = resolveSearchTab('from:Athene CVE', members);
    expect(query.text, 'CVE');
    expect(query.authors, [athene]);
    expect(query.unresolved, isNull);
    expect(resolveSearchTab('from:@athene CVE', members).authors, [athene]);
  });

  test('unknown names are reported; plain text passes', () {
    expect(resolveSearchTab('from:Nobody CVE', members).unresolved, 'Nobody');
    expect(resolveSearchTab('CVE', members).authors, isNull);
  });
}
