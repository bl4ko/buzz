import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../shared/relay/relay.dart';

abstract final class OlympusKind {
  static const agent = 30190;
  static const workspace = 30191;
  static const proposal = 30192;
  static const usage = 30193;
  static const changeRequest = 44310;
  static const changeResult = 44311;

  static const state = [agent, workspace, proposal, usage];
}

const masterAgentRole = 'master';
final _hexKey = RegExp(r'^[0-9a-f]{64}$');

typedef Json = Map<String, Object?>;

Json? _object(Object? value) =>
    value is Map ? value.cast<String, Object?>() : null;

String? _text(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

List<String> _texts(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];

List<Json> _objects(Object? value) => value is List
    ? value.whereType<Map>().map((e) => e.cast<String, Object?>()).toList()
    : const [];

List<String>? _fieldList(Object? value) => value is List ? _texts(value) : null;

String? _hex(Object? value) {
  final candidate = _text(value)?.toLowerCase();
  return candidate != null && _hexKey.hasMatch(candidate) ? candidate : null;
}

String? _singleTag(NostrEvent event, String name) {
  final values = event.tags.where((tag) => tag.isNotEmpty && tag[0] == name);
  return values.length == 1 && values.first.length > 1 ? values.first[1] : null;
}

Json? _content(NostrEvent event) {
  try {
    final content = _object(jsonDecode(event.content));
    return content != null && content['v'] == 1 ? content : null;
  } catch (_) {
    return null;
  }
}

bool _isNewer(NostrEvent candidate, NostrEvent current) =>
    candidate.createdAt > current.createdAt ||
    (candidate.createdAt == current.createdAt &&
        candidate.id.compareTo(current.id) < 0);

/// Keeps the newest event for each addressable Olympus coordinate.
Map<String, NostrEvent> mergeOlympusEvents(
  Map<String, NostrEvent> current,
  Iterable<NostrEvent> incoming,
) {
  final merged = Map<String, NostrEvent>.of(current);
  for (final event in incoming) {
    if (!OlympusKind.state.contains(event.kind)) continue;
    final d = _singleTag(event, 'd');
    final status = _singleTag(event, 'status');
    if (d == null || d.isEmpty || (status != 'active' && status != 'deleted')) {
      continue;
    }
    final key = '${event.kind}:${event.pubkey}:$d';
    final existing = merged[key];
    if (existing == null || _isNewer(event, existing)) merged[key] = event;
  }
  return merged;
}

enum OlympusPhase { pending, enrolled, ready, online, suspended }

OlympusPhase? _phase(String? value) => switch (value) {
  'Pending' => OlympusPhase.pending,
  'Enrolled' => OlympusPhase.enrolled,
  'Ready' => OlympusPhase.ready,
  'Online' => OlympusPhase.online,
  'Suspended' => OlympusPhase.suspended,
  _ => null,
};

@immutable
class OlympusEgressRule {
  const OlympusEgressRule({
    this.host,
    this.cidr,
    this.preset,
    this.ports = const [],
  });
  final String? host;
  final String? cidr;
  final String? preset;
  final List<int> ports;

  String get label {
    final target = preset != null
        ? 'preset $preset'
        : host ?? cidr ?? 'unknown';
    return ports.isEmpty ? target : '$target:${ports.join(',')}';
  }
}

@immutable
class OlympusSecretRef {
  const OlympusSecretRef(this.name, this.env);
  final String name;
  final String? env;
}

@immutable
class OlympusAgentSpec {
  const OlympusAgentSpec({
    required this.harness,
    required this.model,
    required this.pool,
    this.template,
    this.effort,
    this.suspend = false,
    this.mcpServers = const [],
    this.memoryBank,
    this.egress = const [],
    this.secrets = const [],
    this.gitSources = const [],
    this.skills = const [],
    this.kubernetesRole,
    this.runtimeClass,
    this.instructionsFromRepo,
    this.respondTo = const [],
    this.displayName,
    this.picture,
    this.about,
  });

  final String harness;
  final String model;
  final String pool;
  final String? template;
  final String? effort;
  final bool suspend;
  final List<String> mcpServers;
  final String? memoryBank;
  final List<OlympusEgressRule> egress;
  final List<OlympusSecretRef> secrets;
  final List<String> gitSources;
  final List<String> skills;
  final String? kubernetesRole;
  final String? runtimeClass;
  final String? instructionsFromRepo;
  final List<String> respondTo;
  final String? displayName;
  final String? picture;
  final String? about;

  static OlympusAgentSpec? parse(Object? value) {
    final spec = _object(value);
    if (spec == null) return null;
    final template = _text(spec['template']);
    final harness = _text(spec['harness']);
    final model = _text(spec['model']);
    final pool = _text(spec['pool']);
    if ((harness == null || model == null || pool == null) &&
        template == null) {
      return null;
    }
    final memory = _object(spec['memory']);
    final profile = _object(spec['profile']);
    final from = _object(spec['instructionsFrom']);
    return OlympusAgentSpec(
      harness: harness ?? '',
      model: model ?? '',
      pool: pool ?? '',
      template: template,
      effort: _text(spec['effort']),
      suspend: spec['suspend'] == true,
      mcpServers: [
        for (final server in _objects(spec['mcpServers']))
          ?_text(server['name']),
      ],
      memoryBank: memory == null ? null : _text(memory['bank']) ?? 'private',
      egress: [
        for (final rule in _objects(spec['egress']))
          OlympusEgressRule(
            host: _text(rule['host']),
            cidr: _text(rule['cidr']),
            preset: _text(rule['preset']),
            ports: rule['ports'] is List
                ? (rule['ports'] as List).whereType<int>().toList()
                : const [],
          ),
      ],
      secrets: [
        for (final secret in _objects(spec['secrets']))
          if (_text(secret['name']) case final name?)
            OlympusSecretRef(name, _text(secret['env'])),
      ],
      gitSources: [
        for (final source in _objects(spec['gitSources']))
          if (_text(source['name']) case final name?)
            '$name (${_text(source['access']) ?? 'read'})',
      ],
      skills: [
        for (final skill in _objects(spec['skills']))
          if (_text(skill['repo']) case final repo?)
            if (_text(skill['name']) case final name?) '$repo/$name',
      ],
      kubernetesRole: _text(spec['kubernetesRole']),
      runtimeClass: _text(spec['runtimeClass']),
      instructionsFromRepo: from == null
          ? null
          : [?_text(from['skillsRepo']), ?_text(from['path'])].join(':'),
      respondTo: [
        if (spec['respondTo'] case final List<Object?> keys)
          for (final key in keys) ?_hex(key),
      ],
      displayName: _text(profile?['displayName']),
      picture: _text(profile?['picture']),
      about: _text(profile?['about']),
    );
  }
}

@immutable
class OlympusSchedule {
  const OlympusSchedule({
    required this.name,
    this.cron,
    this.timeZone,
    this.suspend = false,
    this.asAgent = false,
    this.hasPrompt = false,
    this.hasScript = false,
    this.lastRunTime,
    this.lastResult,
    this.gitopsFields,
  });

  final String name;
  final String? cron;
  final String? timeZone;
  final bool suspend;
  final bool asAgent;
  final bool hasPrompt;
  final bool hasScript;
  final DateTime? lastRunTime;
  final String? lastResult;
  final List<String>? gitopsFields;

  String get mode {
    if (asAgent) return 'Script as the agent';
    if (hasPrompt && hasScript) return 'Script, then prompt';
    if (hasScript) return 'Script';
    return 'Prompt';
  }

  /// Actions need an operator that publishes field ownership.
  bool get supportsActions => gitopsFields != null;
}

@immutable
class OlympusAgent {
  const OlympusAgent({
    required this.author,
    required this.createdAt,
    required this.d,
    required this.workspace,
    required this.namespace,
    required this.name,
    required this.spec,
    required this.phase,
    this.owner,
    this.managedBy,
    this.role,
    this.effectiveSpec,
    this.gitopsFields,
    this.egressMode,
    this.schedules = const [],
    this.reason,
    this.publicKey,
    this.lastActivity,
    this.instructionsFile,
    this.lastError,
  });

  final String author;
  final int createdAt;
  final String d;
  final String workspace;
  final String namespace;
  final String name;
  final String? owner;
  final String? managedBy;
  final String? role;
  final OlympusAgentSpec spec;
  final OlympusAgentSpec? effectiveSpec;
  final List<String>? gitopsFields;
  final String? egressMode;
  final List<OlympusSchedule> schedules;
  final OlympusPhase phase;
  final String? reason;
  final String? publicKey;
  final DateTime? lastActivity;

  /// `repo/path` of the instructions file in Olympus git.
  final String? instructionsFile;

  /// The first false condition: reason, then message.
  final ({String title, String? detail})? lastError;

  bool get isMaster => role == masterAgentRole;
  OlympusAgentSpec get resolved => effectiveSpec ?? spec;
  String get label => spec.displayName ?? name;

  static OlympusAgent? parse(NostrEvent event) {
    if (event.kind != OlympusKind.agent ||
        _singleTag(event, 'status') != 'active') {
      return null;
    }
    final d = _singleTag(event, 'd');
    final content = _content(event);
    if (d == null || content == null) return null;
    final name = _text(content['name']);
    final workspace = _text(content['workspace']);
    final spec = OlympusAgentSpec.parse(content['spec']);
    final status = _object(content['status']);
    final phase = _phase(_text(status?['phase']));
    if (name == null || workspace == null || spec == null || phase == null) {
      return null;
    }
    return OlympusAgent(
      author: event.pubkey,
      createdAt: event.createdAt,
      d: d,
      workspace: workspace,
      namespace: _text(content['namespace']) ?? '',
      name: name,
      owner: _hex(content['owner']),
      managedBy: _text(content['managedBy']),
      role: _text(content['role']),
      spec: spec,
      effectiveSpec: OlympusAgentSpec.parse(content['effectiveSpec']),
      gitopsFields: _fieldList(content['gitopsFields']),
      egressMode: _text(status?['egressMode']),
      schedules: [
        for (final schedule in _objects(content['schedules']))
          if (_text(schedule['name']) case final scheduleName?)
            OlympusSchedule(
              name: scheduleName,
              cron: _text(schedule['cron']),
              timeZone: _text(schedule['timeZone']),
              suspend: schedule['suspend'] == true,
              asAgent: schedule['asAgent'] == true,
              hasPrompt: _text(schedule['prompt']) != null,
              hasScript: _object(schedule['script'])?.isNotEmpty ?? false,
              lastRunTime: DateTime.tryParse(
                _text(schedule['lastRunTime']) ?? '',
              ),
              lastResult: _text(schedule['lastResult']),
              gitopsFields: _fieldList(schedule['gitopsFields']),
            ),
      ],
      phase: phase,
      reason: _text(status?['reason']),
      publicKey: _hex(status?['publicKey']),
      lastActivity: DateTime.tryParse(_text(status?['lastActivity']) ?? ''),
      instructionsFile: switch (_object(content['instructionsFile'])) {
        final file?
            when _text(file['repo']) != null && _text(file['path']) != null =>
          '${_text(file['repo'])}/${_text(file['path'])}',
        _ => null,
      },
      lastError: _lastError(status?['conditions']),
    );
  }
}

({String title, String? detail})? _lastError(Object? conditions) {
  for (final condition in _objects(conditions)) {
    if (condition['status'] != 'False') continue;
    final title = _text(condition['reason']) ?? _text(condition['type']);
    if (title == null) continue;
    final message = _text(condition['message']);
    return (title: title, detail: message == title ? null : message);
  }
  return null;
}

/// The newest agent state for [publicKey] that [me] owns.
OlympusAgent? findOwnedOlympusAgent(
  Iterable<OlympusAgent> agents,
  String? me,
  String publicKey,
) {
  final owner = me?.toLowerCase();
  final key = publicKey.toLowerCase();
  if (owner == null || owner.isEmpty) return null;
  OlympusAgent? match;
  for (final agent in agents) {
    if (agent.publicKey != key || agent.owner != owner) continue;
    if (match == null || agent.createdAt > match.createdAt) match = agent;
  }
  return match;
}

@immutable
class OlympusWorkspace {
  const OlympusWorkspace({
    required this.author,
    required this.name,
    this.suspend = false,
    this.phase = 'Pending',
  });

  final String author;
  final String name;
  final bool suspend;
  final String phase;

  static OlympusWorkspace? parse(NostrEvent event) {
    if (event.kind != OlympusKind.workspace ||
        _singleTag(event, 'status') != 'active') {
      return null;
    }
    final content = _content(event);
    final name = _text(content?['name']);
    if (content == null || name == null) return null;
    return OlympusWorkspace(
      author: event.pubkey,
      name: name,
      suspend: _object(content['spec'])?['suspend'] == true,
      phase: _text(_object(content['status'])?['phase']) ?? 'Pending',
    );
  }
}

@immutable
class OlympusWorkspaceGroup {
  const OlympusWorkspaceGroup({
    required this.name,
    required this.author,
    required this.workspace,
    required this.agents,
  });

  final String name;
  final String author;
  final OlympusWorkspace? workspace;
  final List<OlympusAgent> agents;
}

List<OlympusWorkspaceGroup> groupOlympusAgents(Iterable<NostrEvent> events) {
  final workspaces = <String, OlympusWorkspace>{};
  final agents = <String, List<OlympusAgent>>{};
  for (final event in events) {
    if (OlympusWorkspace.parse(event) case final workspace?) {
      workspaces['${workspace.author}:${workspace.name}'] = workspace;
    } else if (OlympusAgent.parse(event) case final agent?) {
      (agents['${agent.author}:${agent.workspace}'] ??= []).add(agent);
    }
  }
  final keys = {...workspaces.keys, ...agents.keys};
  final groups = [
    for (final key in keys)
      OlympusWorkspaceGroup(
        author: key.substring(0, key.indexOf(':')),
        name: key.substring(key.indexOf(':') + 1),
        workspace: workspaces[key],
        agents: (agents[key] ?? [])..sort((a, b) => a.name.compareTo(b.name)),
      ),
  ]..sort((a, b) => a.name.compareTo(b.name));
  return groups;
}

OlympusAgent? findMasterAgent(Iterable<OlympusWorkspaceGroup> groups) {
  final masters = [
    for (final group in groups)
      for (final agent in group.agents)
        if (agent.isMaster && agent.publicKey != null) agent,
  ];
  masters.sort((a, b) {
    final suspended =
        (a.phase == OlympusPhase.suspended ? 1 : 0) -
        (b.phase == OlympusPhase.suspended ? 1 : 0);
    if (suspended != 0) return suspended;
    final workspace = a.workspace.compareTo(b.workspace);
    return workspace != 0 ? workspace : a.name.compareTo(b.name);
  });
  return masters.firstOrNull;
}

/// A field is locked when git owns it, an ancestor, or a descendant of it.
/// Without ownership data (old operator) a gitops object is fully locked.
bool olympusFieldLocked({
  required String? managedBy,
  required List<String>? gitopsFields,
  required String path,
}) {
  if (gitopsFields == null) return managedBy == 'gitops';
  return gitopsFields.any(
    (field) =>
        field == path ||
        field.startsWith('$path.') ||
        path.startsWith('$field.'),
  );
}

enum OlympusProposalPhase {
  pending,
  applied,
  rejected,
  refused,
  failed,
  expired,
}

@immutable
class OlympusProposalDiff {
  const OlympusProposalDiff(this.path, this.from, this.to);
  final String path;
  final String? from;
  final String? to;
}

@immutable
class OlympusProposal {
  const OlympusProposal({
    required this.author,
    required this.name,
    required this.workspace,
    required this.requester,
    required this.requesterKey,
    required this.targetKind,
    required this.targetName,
    required this.operation,
    required this.reason,
    required this.diff,
    required this.diffTruncated,
    required this.highRisk,
    required this.createdAt,
    required this.expiresAt,
    required this.digest,
    required this.phase,
    this.resultReason,
    this.decidedAt,
  });

  final String author;
  final String name;
  final String workspace;
  final String requester;
  final String? requesterKey;
  final String targetKind;
  final String targetName;
  final String operation;
  final String reason;
  final List<OlympusProposalDiff> diff;
  final bool diffTruncated;
  final List<String> highRisk;
  final int createdAt;
  final int expiresAt;
  final String digest;
  final OlympusProposalPhase phase;
  final String? resultReason;
  final int? decidedAt;

  String get key => 'proposal:$author:$name';
  bool get isHighRisk => highRisk.isNotEmpty;
  bool isOpen(int now) =>
      phase == OlympusProposalPhase.pending && expiresAt > now;
  OlympusProposalPhase statusAt(int now) =>
      phase == OlympusProposalPhase.pending && expiresAt <= now
      ? OlympusProposalPhase.expired
      : phase;
  String get title =>
      '$requester proposes to $operation $targetKind $targetName';

  static const _targetKinds = {'Agent', 'Schedule', 'Workspace'};
  static const _operations = {'create', 'patch', 'delete'};

  static OlympusProposal? parse(NostrEvent event, Set<String> operators) {
    if (event.kind != OlympusKind.proposal ||
        !operators.contains(event.pubkey) ||
        _singleTag(event, 'status') != 'active') {
      return null;
    }
    final content = _content(event);
    final target = _object(content?['target']);
    if (content == null || target == null) return null;
    final name = _text(content['name']);
    final workspace = _text(target['workspace']);
    final targetKind = _text(target['kind']);
    final targetName = _text(target['name']);
    final operation = _text(content['operation']);
    final phase = OlympusProposalPhase.values
        .where((value) => value.name == content['phase'])
        .firstOrNull;
    final digest = _hex(content['digest']);
    final workspaceTag = _singleTag(event, 'workspace');
    final createdAt = content['createdAt'];
    final expiresAt = content['expiresAt'];
    final rawDiff = content['diff'];
    if (name == null ||
        name != _singleTag(event, 'd') ||
        workspace == null ||
        (workspaceTag != null && workspaceTag != workspace) ||
        !_targetKinds.contains(targetKind) ||
        targetName == null ||
        !_operations.contains(operation) ||
        phase == null ||
        digest == null ||
        rawDiff is! List ||
        content['reason'] is! String ||
        createdAt is! num ||
        expiresAt is! num) {
      return null;
    }
    final diff = <OlympusProposalDiff>[];
    for (final entry in rawDiff) {
      final item = _object(entry);
      final path = _text(item?['path']);
      final from = item?['from'];
      final to = item?['to'];
      if (path == null ||
          (from != null && from is! String) ||
          (to != null && to is! String)) {
        return null;
      }
      diff.add(OlympusProposalDiff(path, from as String?, to as String?));
    }
    final result = _object(content['result']);
    return OlympusProposal(
      author: event.pubkey,
      name: name,
      workspace: workspace,
      requester: _text(content['requester']) ?? 'unknown agent',
      requesterKey:
          _hex(content['requesterKey']) ?? _hex(_singleTag(event, 'requester')),
      targetKind: targetKind!,
      targetName: targetName,
      operation: operation!,
      reason: content['reason'] as String,
      diff: diff,
      diffTruncated: content['diffTruncated'] == true,
      highRisk: _texts(content['highRisk']),
      createdAt: createdAt.toInt(),
      expiresAt: expiresAt.toInt(),
      digest: digest,
      phase: phase,
      resultReason: _text(result?['reason']),
      decidedAt: (result?['at'] as num?)?.toInt(),
    );
  }
}

List<OlympusProposal> listOlympusProposals(
  Iterable<NostrEvent> events,
  Set<String> operators,
) =>
    [for (final event in events) ?OlympusProposal.parse(event, operators)]
      ..sort((a, b) {
        final time = b.createdAt.compareTo(a.createdAt);
        return time != 0 ? time : a.name.compareTo(b.name);
      });

/// Decodes a diff value (JSON text) for display; strings lose their quotes.
String? olympusDiffText(String? raw) {
  if (raw == null) return null;
  try {
    final value = jsonDecode(raw);
    if (value is String) return value;
    return raw.length > 80 && value is Object
        ? const JsonEncoder.withIndent('  ').convert(value)
        : raw;
  } catch (_) {
    return raw;
  }
}

const _subsetTokenTypes = {'cached_input', 'reasoning_output'};

@immutable
class OlympusUsageWindow {
  const OlympusUsageWindow({
    required this.models,
    this.turns = 0,
    this.runs = 0,
    this.failedRuns = 0,
    this.apiErrors = 0,
  });

  /// Total tokens by model, largest first.
  final List<({String model, int tokens})> models;
  final int turns;
  final int runs;
  final int failedRuns;
  final int apiErrors;

  int get tokens => models.fold(0, (sum, entry) => sum + entry.tokens);

  static int _count(Object? value) =>
      value is num && value.isFinite && value > 0 ? value.round() : 0;

  static OlympusUsageWindow? parse(Object? value) {
    final window = _object(value);
    if (window == null) return null;
    final models = <({String model, int tokens})>[];
    for (final MapEntry(key: model, value: types)
        in (_object(window['tokens']) ?? const <String, Object?>{}).entries) {
      final byType = _object(types);
      if (model.isEmpty || byType == null) continue;
      final total = byType['total'] is num
          ? _count(byType['total'])
          : byType.entries
                .where((entry) => !_subsetTokenTypes.contains(entry.key))
                .fold(0, (sum, entry) => sum + _count(entry.value));
      if (total > 0) models.add((model: model, tokens: total));
    }
    models.sort((a, b) {
      final size = b.tokens.compareTo(a.tokens);
      return size != 0 ? size : a.model.compareTo(b.model);
    });
    return OlympusUsageWindow(
      models: models,
      turns: _count(window['turns']),
      runs: _count(window['runs']),
      failedRuns: _count(window['failedRuns']),
      apiErrors: _count(window['apiErrors']),
    );
  }
}

@immutable
class OlympusAgentUsage {
  const OlympusAgentUsage({
    required this.author,
    required this.d,
    required this.workspace,
    required this.name,
    required this.at,
    required this.windows,
  });

  final String author;
  final String d;
  final String workspace;
  final String name;
  final int at;
  final Map<String, OlympusUsageWindow?> windows;

  static OlympusAgentUsage? parse(NostrEvent event, Set<String> operators) {
    if (event.kind != OlympusKind.usage ||
        !operators.contains(event.pubkey) ||
        _singleTag(event, 'status') != 'active') {
      return null;
    }
    final d = _singleTag(event, 'd');
    final content = _content(event);
    final workspace = _text(content?['workspace']);
    final namespace = _text(content?['namespace']);
    final name = _text(content?['name']);
    if (content == null ||
        workspace == null ||
        namespace == null ||
        name == null ||
        d != '$namespace/$name') {
      return null;
    }
    final windows = _object(content['windows']);
    final at = content['at'];
    return OlympusAgentUsage(
      author: event.pubkey,
      d: d!,
      workspace: workspace,
      name: name,
      at: at is num ? at.toInt() : event.createdAt,
      windows: {
        for (final key in const ['24h', '7d'])
          key: OlympusUsageWindow.parse(windows?[key]),
      },
    );
  }
}

String formatCompactCount(int value) {
  const units = [(1e12, 'T'), (1e9, 'B'), (1e6, 'M'), (1e3, 'k')];
  for (final (size, suffix) in units) {
    if (value >= size * 0.9995) {
      final scaled = value / size;
      final text = scaled.toStringAsFixed(scaled < 10 ? 1 : 0);
      return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}$suffix';
    }
  }
  return '$value';
}

const _maxQuoteLength = 8000;

String quoteMarkdown(String text) {
  final trimmed = text.replaceAll(RegExp(r'\r\n?'), '\n').trim();
  final clipped = trimmed.length > _maxQuoteLength
      ? '${trimmed.substring(0, _maxQuoteLength).trimRight()}…'
      : trimmed;
  return clipped
      .split('\n')
      .map((line) => line.trim().isEmpty ? '>' : '> ${line.trimRight()}')
      .join('\n');
}

/// The Ask draft: the quoted text, then its message link and a space for the
/// question.
String buildAskDraft({String? quote, String? link}) {
  final quoted = quote != null && quote.trim().isNotEmpty
      ? quoteMarkdown(quote)
      : null;
  if (link != null) return [?quoted, '$link '].join('\n\n');
  return quoted == null ? '' : '$quoted\n\n';
}

String mergeAskDraft(String? existing, String next) {
  final current = (existing ?? '').trimRight();
  if (current.isEmpty) return next;
  if (next.isEmpty || current.contains(next.trim())) return current;
  return '$current\n\n$next';
}
