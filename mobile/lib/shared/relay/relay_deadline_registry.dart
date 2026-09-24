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

  /// The deadline error [key] settled on, or null when it may run.
  Object? terminalError(String key) => _terminal[key];

  bool isTerminal(String key) => _terminal.containsKey(key);

  /// Records [error] against [key] when it is a relay deadline.
  /// Returns whether it was one.
  bool record(String key, Object error) {
    if (!isRelayDeadlineError(error)) return false;
    _terminal[key] = error;
    return true;
  }

  void clear(String key) => _terminal.remove(key);
}

/// Request identity for [filters]: equal filters address the same work.
String relayRequestKey(List<NostrFilter> filters) =>
    jsonEncode([for (final filter in filters) filter.toJson()]);

/// Scoped to the relay and signing identity: switching either starts empty,
/// so a terminal outcome never crosses communities or accounts.
final relayDeadlineRegistryProvider = Provider<RelayDeadlineRegistry>((ref) {
  ref.watch(relayConfigProvider.select((c) => (c.baseUrl, c.nsec)));
  return RelayDeadlineRegistry();
});
