import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'nostr_models.dart';
import 'relay_closed_policy.dart';
import 'relay_provider.dart';

/// Requests that settled on a relay statement deadline, keyed by identity.
///
/// Every automatic owner of a request (timers, reconnect, backstop, resume,
/// live activity, recounts) consults the same entry, so a second owner cannot
/// replay a scan the first declared terminal. Only an explicit user action or
/// a completed request clears an entry; a changed request has a new key.
class RelayDeadlineRegistry {
  final _terminal = <String, Object>{};
  final _epochs = <String, int>{};

  /// The deadline error [key] settled on, or null when it may run.
  Object? terminalError(String key) => _terminal[key];

  bool isTerminal(String key) => _terminal.containsKey(key);

  /// Token for an attempt starting now; pass it to [record] so a reset or
  /// fenced success that happens meanwhile wins over the old attempt.
  int attempt(String key) => _epochs[key] ?? 0;

  /// Records [error] against [key] when it is a relay deadline.
  /// Returns whether it was one. An [attempt] older than the latest [clear]
  /// is still classified but no longer recorded.
  bool record(String key, Object error, {int? attempt}) {
    if (!isRelayDeadlineError(error)) return false;
    if (attempt == null || attempt == this.attempt(key)) {
      _terminal[key] = error;
    }
    return true;
  }

  /// Explicit reset or fenced complete result; supersedes open attempts.
  void clear(String key) {
    _terminal.remove(key);
    _epochs[key] = attempt(key) + 1;
  }

  /// [clear]s every terminal key starting with [prefix].
  void clearPrefix(String prefix) {
    for (final key in [..._terminal.keys.where((k) => k.startsWith(prefix))]) {
      clear(key);
    }
  }
}

/// Request identity for [filters]: equal filters address the same work,
/// whatever order the caller built them in.
String relayRequestKey(List<NostrFilter> filters) => jsonEncode(
  [for (final filter in filters) jsonEncode(filter.toJson())]..sort(),
);

/// Scoped to the relay and signing identity: switching either starts empty,
/// so a terminal outcome never crosses communities or accounts.
final relayDeadlineRegistryProvider = Provider<RelayDeadlineRegistry>((ref) {
  ref.watch(relayConfigProvider.select((c) => (c.baseUrl, c.nsec)));
  return RelayDeadlineRegistry();
});
