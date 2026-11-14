import 'dart:convert';

import 'package:buzz/features/olympus/olympus_provider.dart';
import 'package:buzz/features/olympus/olympus_state.dart';
import 'package:buzz/shared/relay/relay.dart';

final operatorKey = 'b' * 64;
final ownerKey = 'a' * 64;
final zeusKey = 'c' * 64;
final argusKey = 'd' * 64;
final digest = 'e' * 64;

int _id = 0;

NostrEvent olympusEvent({
  required int kind,
  required String d,
  required Object? content,
  String status = 'active',
  int createdAt = 1000,
  String? author,
  List<List<String>> extraTags = const [],
}) => NostrEvent(
  id: (++_id).toRadixString(16).padLeft(64, '0'),
  pubkey: author ?? operatorKey,
  createdAt: createdAt,
  kind: kind,
  tags: [
    ['d', d],
    ['p', ownerKey],
    ['p', operatorKey],
    ['status', status],
    ...extraTags,
  ],
  content: content == null ? '' : jsonEncode(content),
  sig: '',
);

NostrEvent agentEvent({
  required String workspace,
  required String name,
  String phase = 'Online',
  String? role,
  String? publicKey,
  List<String>? gitopsFields = const [],
  bool suspend = false,
  List<Map<String, Object?>> schedules = const [],
  int createdAt = 1000,
}) => olympusEvent(
  kind: OlympusKind.agent,
  d: 'olympus-$workspace/$name',
  createdAt: createdAt,
  extraTags: [
    ['workspace', workspace],
  ],
  content: {
    'v': 1,
    'workspace': workspace,
    'namespace': 'olympus-$workspace',
    'name': name,
    'owner': ownerKey,
    'managedBy': gitopsFields == null || gitopsFields.isEmpty ? null : 'gitops',
    'role': role,
    'gitopsFields': gitopsFields,
    'spec': {
      'harness': 'claude-code',
      'model': 'claude-opus-5-5',
      'pool': 'claude',
      'effort': 'high',
      'suspend': suspend,
      'mcpServers': [
        {'name': 'olympus', 'tools': null},
      ],
      'memory': {'bank': 'private'},
      'egress': [
        {
          'host': 'api.github.com',
          'cidr': null,
          'preset': null,
          'ports': [443],
        },
      ],
      'secrets': [
        {'name': 'github-token', 'env': 'GH_TOKEN'},
      ],
      'profile': {'displayName': '${name[0].toUpperCase()}${name.substring(1)}'},
    },
    'schedules': schedules,
    'status': {
      'phase': phase,
      'reason': phase == 'Online' ? null : 'Suspended',
      'publicKey': publicKey,
      'lastActivity': '2026-11-14T08:00:00Z',
    },
  },
);

NostrEvent workspaceEvent(String name) => olympusEvent(
  kind: OlympusKind.workspace,
  d: name,
  content: {
    'v': 1,
    'name': name,
    'namespace': 'olympus-$name',
    'spec': {'suspend': false},
    'status': {'phase': 'Ready'},
  },
);

NostrEvent proposalEvent({
  String name = 'p-aada7279a890',
  String phase = 'pending',
  List<String> highRisk = const [],
  int createdAt = 1000,
  int expiresAt = 4102444800,
}) => olympusEvent(
  kind: OlympusKind.proposal,
  d: name,
  extraTags: [
    ['workspace', 'dev'],
    ['requester', zeusKey],
  ],
  content: {
    'v': 1,
    'name': name,
    'requester': 'zeus/zeus',
    'requesterKey': zeusKey,
    'target': {
      'kind': 'Agent',
      'namespace': 'olympus-dev',
      'name': 'proof',
      'workspace': 'dev',
    },
    'operation': 'patch',
    'patch': '{"spec":{"suspend":true}}',
    'reason': 'Proof is idle; suspend it to save tokens.',
    'diff': [
      {'path': 'spec.suspend', 'from': 'false', 'to': 'true'},
    ],
    'highRisk': highRisk,
    'createdAt': createdAt,
    'expiresAt': expiresAt,
    'digest': digest,
    'phase': phase,
    'result': null,
  },
);

NostrEvent usageEvent({
  required String workspace,
  required String name,
  Map<String, Object?>? day,
}) => olympusEvent(
  kind: OlympusKind.usage,
  d: 'olympus-$workspace/$name',
  content: {
    'v': 1,
    'workspace': workspace,
    'namespace': 'olympus-$workspace',
    'name': name,
    'harness': 'claude-code',
    'at': 2000,
    'windows': {'24h': day, '7d': day},
    'lastRun': null,
  },
);

OlympusSnapshot snapshotOf(
  List<NostrEvent> events, {
  Map<String, OlympusRequestState> requests = const {},
}) => OlympusSnapshot(
  me: ownerKey,
  events: mergeOlympusEvents({}, events),
  loaded: true,
  requests: requests,
);

typedef SentChange = ({String key, OlympusChangeTarget target, OlympusChange change});

class FakeOlympusNotifier extends OlympusNotifier {
  FakeOlympusNotifier(this.initial);
  final OlympusSnapshot initial;
  final sent = <SentChange>[];

  @override
  OlympusSnapshot build() => initial;

  @override
  Future<OlympusRequestState?> submit(
    String key,
    OlympusChangeTarget target,
    OlympusChange change, {
    OlympusChangeSigner? signer,
    Duration timeout = olympusResultTimeout,
  }) async {
    sent.add((key: key, target: target, change: change));
    return OlympusRequestState(OlympusRequestPhase.accepted, change.action);
  }
}
