import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every popover action id has a sort position', () {
    final source = File(
      'lib/features/channels/message_actions/message_action_popover.dart',
    ).readAsStringSync();
    final ids = {
      for (final action in RegExp(
        r'_PopoverMessageAction\(\s*id: ([^,]+),',
      ).allMatches(source))
        for (final id in RegExp(r"'(\w+)'").allMatches(action.group(1)!))
          id.group(1)!,
    };
    final orderStart = source.indexOf('const actionOrder = {');
    final order = source.substring(
      orderStart,
      source.indexOf('};', orderStart),
    );
    final ordered = RegExp(
      r"'(\w+)':",
    ).allMatches(order).map((m) => m.group(1)!).toSet();
    expect(ids, contains('later'));
    expect(ids.difference(ordered), isEmpty);
    final symbolStart = source.indexOf('String get iosSymbol');
    final symbols = source.substring(
      symbolStart,
      source.indexOf('};', symbolStart),
    );
    expect(symbols, contains("'later' => 'bookmark'"));
  });
}
