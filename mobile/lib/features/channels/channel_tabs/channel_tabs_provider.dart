import 'dart:async';
import 'dart:math';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/relay/relay.dart';
import '../channel_management_provider.dart';
import 'channel_tabs_model.dart';

class ChannelTabsState {
  const ChannelTabsState(this.channelId, [this.events = const []]);
  final String channelId;
  final List<NostrEvent> events;
  LatestChannelTabs get latest =>
      latestChannelTabs(events, channelId: channelId);
}

class ChannelTabsNotifier extends Notifier<ChannelTabsState> {
  ChannelTabsNotifier(this.channelId);

  final String channelId;
  (String, String?)? _scope;
  late ChannelTabsState _tabs = ChannelTabsState(channelId);

  @override
  ChannelTabsState build() {
    final config = ref.watch(relayConfigProvider);
    final connected = ref.watch(
      relaySessionProvider.select((s) => s.status == SessionStatus.connected),
    );
    final scope = (config.baseUrl, config.nsec);
    if (scope != _scope) {
      _scope = scope;
      _tabs = ChannelTabsState(channelId);
    }
    if (connected) {
      var disposed = false;
      void Function()? unsubscribe;
      ref.onDispose(() {
        disposed = true;
        unsubscribe?.call();
      });
      unawaited(
        ref
            .read(relaySessionProvider.notifier)
            .subscribe(
              NostrFilter(
                kinds: const [EventKind.channelTabs],
                tags: {
                  '#h': [channelId],
                },
                limit: 200,
              ),
              (event) {
                if (!disposed) receive(event);
              },
            )
            .then(
              (cancel) => disposed ? cancel() : unsubscribe = cancel,
              onError: (Object _) {},
            ),
      );
    }
    return _tabs;
  }

  void receive(NostrEvent event) {
    if (event.kind != EventKind.channelTabs ||
        _tabs.events.any((e) => e.id == event.id)) {
      return;
    }
    _tabs = ChannelTabsState(channelId, [..._tabs.events, event]);
    state = _tabs;
  }

  Future<void> save(List<ChannelTab> tabs) async {
    NostrEvent? signed;
    await ref
        .read(channelActionsProvider)
        .saveChannelTabs(
          channelId: channelId,
          tabs: tabs,
          createdAt: max(
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
            _tabs.latest.createdAt + 1,
          ),
          onSigned: (event) => signed = event,
        );
    final event = signed;
    if (event != null && ref.mounted) receive(event);
  }
}

final channelTabsProvider = NotifierProvider.autoDispose
    .family<ChannelTabsNotifier, ChannelTabsState, String>(
      ChannelTabsNotifier.new,
    );
