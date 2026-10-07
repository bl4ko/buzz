import 'package:buzz/shared/mentions/hidden_mentions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final zeus = 'a' * 64;
  final argus = 'b' * 64;
  final athene = 'c' * 64;
  final names = {zeus: 'Zeus', argus: 'Argus', athene: 'Athene'};

  test('lists p-tagged recipients the text does not mention', () {
    expect(
      hiddenMentionPubkeys(
        'Argus: please supply fresh evidence',
        [
          ['p', argus],
          ['p', athene],
        ],
        names,
        const [],
      ),
      [argus, athene],
    );
  });

  test('omits inline mentions and the sender', () {
    expect(
      hiddenMentionPubkeys(
        '@Zeus please review',
        [
          ['p', zeus],
          ['p', athene.toUpperCase()],
        ],
        names,
        [athene],
      ),
      isEmpty,
    );
  });

  test('ignores mention references, duplicates, and empty tags', () {
    expect(
      hiddenMentionPubkeys(
        'status update',
        [
          ['mention', zeus],
          ['p', argus],
          ['p', argus],
          ['p', ''],
        ],
        const {},
        const [],
      ),
      [argus],
    );
  });
}
