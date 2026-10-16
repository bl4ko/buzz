import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/relay/relay.dart';

void subscribeWhileAlive(
  Ref ref,
  NostrFilter filter,
  void Function(NostrEvent event) onEvent,
) {
  var disposed = false;
  void Function()? unsubscribe;
  ref.onDispose(() {
    disposed = true;
    unsubscribe?.call();
  });
  unawaited(
    ref
        .read(relaySessionProvider.notifier)
        .subscribe(filter, (event) {
          if (!disposed) onEvent(event);
        })
        .then(
          (cancel) => disposed ? cancel() : unsubscribe = cancel,
          onError: (Object _) {},
        ),
  );
}
