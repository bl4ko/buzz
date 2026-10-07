import 'mention_bindings.dart';
import 'mention_tags.dart';

/// Signed `p` recipients that the message text does not show.
List<String> hiddenMentionPubkeys(
  String content,
  List<List<String>> tags,
  Map<String, String> mentionNames,
  Iterable<String?> shownPubkeys,
) {
  final bindings = renderedMentionBindings(
    content,
    mentionNames,
    mentionedPubkeysFromTags(tags),
  );
  final shown = {
    for (final range in mentionOccurrences(content, bindings.keys))
      ...?bindings[range.label.toLowerCase()],
    for (final pubkey in shownPubkeys)
      if (pubkey != null) pubkey.toLowerCase(),
  };
  final hidden = <String>[];
  for (final tag in tags) {
    if (tag.length < 2 || tag[0] != 'p' || tag[1].isEmpty) continue;
    final pubkey = tag[1].toLowerCase();
    if (!shown.contains(pubkey) && !hidden.contains(pubkey)) hidden.add(pubkey);
  }
  return hidden;
}
