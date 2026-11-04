part of 'relay_session.dart';

extension RelaySessionBackgroundHold on RelaySessionNotifier {
  /// Keeps the socket open in the background until the returned callback runs.
  void Function() holdInBackground() {
    final owner = Object();
    _backgroundHolds.add(owner);
    return () {
      if (!_backgroundHolds.remove(owner) || _backgroundHolds.isNotEmpty) {
        return;
      }
      if (_backgroundedAt != null && !_paused) _scheduleBackgroundPause();
    };
  }

  void _scheduleBackgroundPause() {
    _backgroundGraceTimer?.cancel();
    _backgroundGraceTimer = Timer(
      RelaySessionNotifier._backgroundGraceDuration,
      () {
        unawaited(_pauseAfterCallbacks());
      },
    );
  }
}
