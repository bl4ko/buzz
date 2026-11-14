import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/relay/relay.dart';
import '../channels/agent_activity/observer_models.dart';
import '../channels/agent_activity/observer_subscription.dart';
import 'olympus_state.dart';

const olympusResultTimeout = Duration(seconds: 30);
const _olympusLimit = 1000;

/// One Olympus change request (kind 44310): the action and its parameters.
@immutable
class OlympusChange {
  const OlympusChange(this.action, [this.params = const {}]);

  const OlympusChange.suspend() : this('suspend');
  const OlympusChange.resume() : this('resume');
  const OlympusChange.suspendSchedule() : this('suspend-schedule');
  const OlympusChange.resumeSchedule() : this('resume-schedule');
  const OlympusChange.runNow() : this('run-now');

  OlympusChange.approve(OlympusProposal proposal, {bool highRisk = false})
    : this('approve', {
        'proposal': proposal.name,
        'digest': proposal.digest,
        if (highRisk) 'highRisk': true,
      });

  OlympusChange.reject(OlympusProposal proposal, {String? reason})
    : this('reject', {
        'proposal': proposal.name,
        'digest': proposal.digest,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      });

  final String action;
  final Map<String, Object> params;
}

@immutable
class OlympusChangeTarget {
  const OlympusChangeTarget({
    required this.operator,
    required this.workspace,
    this.agent,
    this.schedule,
  });

  final String operator;
  final String workspace;
  final String? agent;
  final String? schedule;
}

final _hexKey = RegExp(r'^[0-9a-f]{64}$');

({String content, List<List<String>> tags}) buildOlympusChangeRequest(
  OlympusChangeTarget target,
  OlympusChange change,
) {
  if (!_hexKey.hasMatch(target.operator)) {
    throw ArgumentError('The operator key is not valid.');
  }
  if (target.workspace.isEmpty) {
    throw ArgumentError('The workspace is missing.');
  }
  final proposal = change.params['proposal'];
  final schedule = target.schedule;
  final scheduleAction =
      change.action.endsWith('-schedule') || change.action == 'run-now';
  if (scheduleAction != (schedule != null) ||
      (schedule != null && target.agent != null)) {
    throw ArgumentError('The ${change.action} action has a bad target.');
  }
  if (proposal != null &&
      (target.agent != null ||
          !_hexKey.hasMatch('${change.params['digest']}'))) {
    throw ArgumentError('The proposal name or digest is not valid.');
  }
  return (
    content: jsonEncode({
      'v': 1,
      'action': change.action,
      'workspace': target.workspace,
      'agent': ?target.agent,
      'schedule': ?schedule,
      ...change.params,
    }),
    tags: [
      ['p', target.operator],
      ['workspace', target.workspace],
      if (target.agent case final agent?) ['agent', agent],
      ?(schedule == null ? null : ['schedule', schedule]),
      ['action', change.action],
      if (proposal is String) ['proposal', proposal],
    ],
  );
}

enum OlympusRequestPhase { pending, accepted, refused, failed }

@immutable
class OlympusRequestState {
  const OlympusRequestState(this.phase, this.action, [this.reason]);
  final OlympusRequestPhase phase;
  final String action;
  final String? reason;
}

OlympusRequestState? parseOlympusChangeResult(
  NostrEvent event, {
  required String requestId,
  required String operator,
  required String action,
}) {
  if (event.kind != OlympusKind.changeResult || event.pubkey != operator) {
    return null;
  }
  final e = event.tags.where((tag) => tag.length > 1 && tag[0] == 'e');
  final status = event.tags.where(
    (tag) => tag.length > 1 && tag[0] == 'status',
  );
  if (e.length != 1 || e.first[1] != requestId || status.length != 1) {
    return null;
  }
  final phase = switch (status.first[1]) {
    'accepted' => OlympusRequestPhase.accepted,
    'refused' => OlympusRequestPhase.refused,
    _ => null,
  };
  if (phase == null) return null;
  String? reason;
  try {
    final content = jsonDecode(event.content);
    if (content is Map && content['reason'] is String) {
      final text = content['reason'] as String;
      if (text.isNotEmpty) reason = text;
    }
  } catch (_) {}
  return OlympusRequestState(phase, action, reason);
}

@immutable
class OlympusSnapshot {
  OlympusSnapshot({
    required this.me,
    required Map<String, NostrEvent> events,
    required this.loaded,
    required this.requests,
  }) : _events = events;

  final String? me;
  final Map<String, NostrEvent> _events;
  final bool loaded;
  final Map<String, OlympusRequestState> requests;

  late final List<OlympusWorkspaceGroup> groups = groupOlympusAgents(
    _events.values,
  );
  late final Set<String> operators = {for (final g in groups) g.author};
  late final List<OlympusAgent> agents = [
    for (final group in groups) ...group.agents,
  ];
  late final OlympusAgent? master = findMasterAgent(groups);
  late final List<OlympusProposal> proposals = listOlympusProposals(
    _events.values,
    operators,
  );
  late final Map<String, OlympusAgentUsage> usage = {
    for (final usage
        in _events.values
            .map((event) => OlympusAgentUsage.parse(event, operators))
            .nonNulls)
      '${usage.author}:${usage.d}': usage,
  };

  OlympusAgentUsage? usageFor(OlympusAgent agent) =>
      usage['${agent.author}:${agent.d}'];

  OlympusAgent? agent(String author, String d) => agents
      .where((agent) => agent.author == author && agent.d == d)
      .firstOrNull;

  int pendingCount(int now, {String? requesterKey}) => proposals
      .where(
        (proposal) =>
            proposal.isOpen(now) &&
            (requesterKey == null || proposal.requesterKey == requesterKey),
      )
      .length;
}

typedef OlympusChangeSigner =
    Future<NostrEvent> Function({
      required int kind,
      required String content,
      required List<List<String>> tags,
      FutureOr<void> Function(NostrEvent event)? onSigned,
    });

class OlympusNotifier extends Notifier<OlympusSnapshot> {
  Map<String, NostrEvent> _events = {};
  final Map<String, OlympusRequestState> _requests = {};
  bool _loaded = false;
  String? _identity;
  void Function()? _unsubscribe;
  Timer? _flush;
  int _epoch = 0;

  @override
  OlympusSnapshot build() {
    final config = ref.watch(relayConfigProvider);
    final me = ref.watch(myPubkeyProvider);
    final status = ref.watch(relaySessionProvider.select((s) => s.status));
    final identity = '${config.baseUrl}|$me';
    if (identity != _identity) {
      _identity = identity;
      _events = {};
      _requests.clear();
      _loaded = false;
      _epoch++;
    }
    ref.onDispose(_stop);
    if (me != null && status == SessionStatus.connected) {
      final epoch = ++_epoch;
      Future.microtask(() => _start(me, epoch));
    }
    return _snapshot(me);
  }

  OlympusSnapshot _snapshot(String? me) => OlympusSnapshot(
    me: me,
    events: _events,
    loaded: _loaded,
    requests: Map.unmodifiable(_requests),
  );

  void _stop() {
    _epoch++;
    _flush?.cancel();
    _flush = null;
    _unsubscribe?.call();
    _unsubscribe = null;
  }

  void _emit() => state = _snapshot(state.me);

  Future<void> _start(String me, int epoch) async {
    if (epoch != _epoch || _unsubscribe != null) return;
    final pending = <NostrEvent>[];
    void apply() {
      _flush = null;
      if (epoch != _epoch || pending.isEmpty) return;
      _events = mergeOlympusEvents(_events, pending);
      pending.clear();
      _emit();
    }

    try {
      final unsubscribe = await ref
          .read(relaySessionProvider.notifier)
          .subscribe(
            NostrFilter(
              kinds: OlympusKind.state,
              tags: {
                '#p': [me],
              },
              limit: _olympusLimit,
            ),
            (event) {
              pending.add(event);
              _flush ??= Timer(const Duration(milliseconds: 50), apply);
            },
            onClosed: (message) {
              debugPrint('olympus: subscription closed: $message');
              if (epoch != _epoch) return;
              _unsubscribe = null;
              _loaded = true;
              _emit();
            },
          );
      if (epoch != _epoch) {
        unsubscribe();
        return;
      }
      _flush?.cancel();
      apply();
      _loaded = true;
      _emit();
      _unsubscribe = unsubscribe;
    } catch (error) {
      debugPrint('olympus: subscribe failed: $error');
    }
  }

  void clearRequest(String key) {
    if (_requests[key]?.phase == OlympusRequestPhase.pending) return;
    if (_requests.remove(key) != null) _emit();
  }

  /// Signs and sends one 44310, then waits for the operator's 44311.
  Future<OlympusRequestState?> submit(
    String key,
    OlympusChangeTarget target,
    OlympusChange change, {
    OlympusChangeSigner? signer,
    Duration timeout = olympusResultTimeout,
  }) async {
    final me = state.me;
    if (me == null || _requests[key]?.phase == OlympusRequestPhase.pending) {
      return null;
    }
    final identity = _identity;
    bool current() => identity == _identity;
    void settle(OlympusRequestState result) {
      if (!current()) return;
      _requests[key] = result;
      _emit();
    }

    settle(OlympusRequestState(OlympusRequestPhase.pending, change.action));
    final result = Completer<OlympusRequestState>();
    void Function()? unsubscribe;
    Timer? timer;
    try {
      final request = buildOlympusChangeRequest(target, change);
      final session = ref.read(relaySessionProvider.notifier);
      final sign =
          signer ??
          SignedEventRelay(
            session: session,
            nsec: ref.read(relayConfigProvider).nsec,
          ).submit;
      await sign(
        kind: OlympusKind.changeRequest,
        content: request.content,
        tags: request.tags,
        onSigned: (event) async {
          unsubscribe = await session.subscribe(
            NostrFilter(
              kinds: const [OlympusKind.changeResult],
              tags: {
                '#e': [event.id],
                '#p': [me],
              },
              limit: 1,
            ),
            (candidate) {
              final parsed = parseOlympusChangeResult(
                candidate,
                requestId: event.id,
                operator: target.operator,
                action: change.action,
              );
              if (parsed != null && !result.isCompleted) {
                result.complete(parsed);
              }
            },
          );
          timer = Timer(timeout, () {
            if (result.isCompleted) return;
            result.complete(
              OlympusRequestState(
                OlympusRequestPhase.failed,
                change.action,
                'No answer from Hephaestus in ${timeout.inSeconds} seconds. '
                'The change can still apply later.',
              ),
            );
          });
        },
      );
      final outcome = await result.future;
      settle(outcome);
      return outcome;
    } catch (error) {
      final failed = OlympusRequestState(
        OlympusRequestPhase.failed,
        change.action,
        error is ArgumentError ? '${error.message}' : '$error',
      );
      settle(failed);
      return failed;
    } finally {
      timer?.cancel();
      unsubscribe?.call();
    }
  }
}

final olympusProvider = NotifierProvider<OlympusNotifier, OlympusSnapshot>(
  OlympusNotifier.new,
);

final olympusMasterProvider = Provider<OlympusAgent?>(
  (ref) => ref.watch(olympusProvider.select((s) => s.master)),
);

int olympusNow() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// Open proposals. The operator republishes a proposal when it expires.
final olympusPendingCountProvider = Provider<int>(
  (ref) => ref.watch(olympusProvider).pendingCount(olympusNow()),
);

const _workingStale = Duration(minutes: 3);
const _turnEnd = {'turn_completed', 'turn_error', 'agent_panic'};
const _turnWork = {'turn_started', 'acp_read', 'acp_write', 'turn_liveness'};

/// An agent is working while its newest turn frame is not a turn end.
bool olympusAgentWorking(List<ObserverFrame> frames, DateTime now) {
  for (final frame in frames.reversed) {
    if (_turnEnd.contains(frame.kind)) return false;
    if (!_turnWork.contains(frame.kind)) continue;
    final at = DateTime.tryParse(frame.timestamp);
    return at != null && now.difference(at) < _workingStale;
  }
  return false;
}

final olympusWorkingAgentsProvider = Provider<Set<String>>((ref) {
  final frames = ref.watch(
    observerRelayProvider.select((s) => s.framesByAgent),
  );
  final now = DateTime.now();
  return {
    for (final MapEntry(key: agent, value: list) in frames.entries)
      if (olympusAgentWorking(list, now)) agent,
  };
});
