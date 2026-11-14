import 'dart:convert';

import 'package:buzz/features/channels/agent_activity/observer_models.dart';
import 'package:buzz/features/olympus/olympus_provider.dart';
import 'package:buzz/features/olympus/olympus_state.dart';
import 'package:buzz/shared/deeplink/deep_link.dart';
import 'package:flutter_test/flutter_test.dart';

import 'olympus_fixtures.dart';

void main() {
  group('Olympus state', () {
    test('parses agents, keeps the newest event, and groups by workspace', () {
      final old = agentEvent(workspace: 'ops', name: 'argus', createdAt: 900);
      final groups = snapshotOf([
        workspaceEvent('ops'),
        old,
        agentEvent(
          workspace: 'ops',
          name: 'argus',
          phase: 'Suspended',
          createdAt: 950,
        ),
        agentEvent(workspace: 'dev', name: 'proof'),
      ]).groups;
      expect(groups.map((group) => group.name), ['dev', 'ops']);
      final argus = groups.last.agents.single;
      expect(argus.phase, OlympusPhase.suspended);
      expect(argus.label, 'Argus');
      expect(argus.spec.secrets.single.name, 'github-token');
      expect(argus.spec.egress.single.label, 'api.github.com:443');
      expect(groups.last.workspace?.phase, 'Ready');
    });

    test('hides tombstones and invalid content', () {
      final snapshot = snapshotOf([
        agentEvent(workspace: 'dev', name: 'proof', createdAt: 1),
        olympusEvent(
          kind: OlympusKind.agent,
          d: 'olympus-dev/proof',
          content: null,
          status: 'deleted',
          createdAt: 2,
        ),
        olympusEvent(
          kind: OlympusKind.agent,
          d: 'olympus-dev/broken',
          content: {'v': 2},
        ),
      ]);
      expect(snapshot.agents, isEmpty);
    });

    test('the master is the role master agent with a key, active first', () {
      final snapshot = snapshotOf([
        agentEvent(
          workspace: 'a',
          name: 'old',
          role: 'master',
          phase: 'Suspended',
          publicKey: argusKey,
        ),
        agentEvent(
          workspace: 'zeus',
          name: 'zeus',
          role: 'master',
          publicKey: zeusKey,
        ),
        agentEvent(workspace: 'b', name: 'nokey', role: 'master'),
      ]);
      expect(snapshot.master?.name, 'zeus');
      expect(snapshotOf([agentEvent(workspace: 'x', name: 'y')]).master, null);
    });

    test('git ownership locks the field, its parents, and its children', () {
      bool locked(List<String>? fields, String path, [String? managedBy]) =>
          olympusFieldLocked(
            managedBy: managedBy,
            gitopsFields: fields,
            path: path,
          );
      expect(locked(['spec.model'], 'spec.model'), isTrue);
      expect(locked(['spec.memory.bank'], 'spec.memory'), isTrue);
      expect(locked(['spec.mcpServers'], 'spec.mcpServers.0'), isTrue);
      expect(locked(['spec.model'], 'spec.suspend'), isFalse);
      expect(locked(null, 'spec.suspend', 'gitops'), isTrue);
      expect(locked(null, 'spec.suspend'), isFalse);
    });

    test('proposals come only from operators and track their deadline', () {
      final snapshot = snapshotOf([
        agentEvent(workspace: 'dev', name: 'proof'),
        proposalEvent(highRisk: ['master agent']),
        proposalEvent(name: 'p-expired', expiresAt: 1500),
        olympusEvent(
          kind: OlympusKind.proposal,
          d: 'p-forged',
          author: argusKey,
          content: jsonDecode(proposalEvent(name: 'p-forged').content),
        ),
      ]);
      expect(snapshot.proposals.map((p) => p.name), [
        'p-aada7279a890',
        'p-expired',
      ]);
      final proposal = snapshot.proposals.first;
      expect(proposal.isHighRisk, isTrue);
      expect(proposal.requesterKey, zeusKey);
      expect(proposal.title, 'zeus/zeus proposes to patch Agent proof');
      expect(snapshot.pendingCount(2000), 1);
      expect(snapshot.pendingCount(2000, requesterKey: argusKey), 0);
      expect(
        snapshot.proposals.last.statusAt(2000),
        OlympusProposalPhase.expired,
      );
    });

    test('usage totals leave out subset token types and never show USD', () {
      final snapshot = snapshotOf([
        agentEvent(workspace: 'ops', name: 'argus'),
        usageEvent(
          workspace: 'ops',
          name: 'argus',
          day: {
            'tokens': {
              'gpt-5.5': {
                'input': 1000,
                'cached_input': 900,
                'output': 200,
                'reasoning_output': 150,
              },
              'claude-opus-5-5': {'total': 5000, 'input': 1},
            },
            'turns': 4,
            'runs': 2,
            'failedRuns': 1,
          },
        ),
      ]);
      final usage = snapshot.usageFor(snapshot.agents.single)!.windows['24h']!;
      expect(usage.models.map((m) => (m.model, m.tokens)), [
        ('claude-opus-5-5', 5000),
        ('gpt-5.5', 1200),
      ]);
      expect(usage.tokens, 6200);
      expect(usage.failedRuns, 1);
      expect(formatCompactCount(6200), '6.2k');
      expect(formatCompactCount(53300000), '53M');
      expect(formatCompactCount(999), '999');
    });

    test(
      'the ask draft quotes the message and keeps a line for the question',
      () {
        expect(
          buildAskDraft(
            quote: 'Line one\n\nline two',
            link: 'buzz://message?x',
          ),
          '> Line one\n>\n> line two\n\nbuzz://message?x ',
        );
        expect(buildAskDraft(quote: 'Why?'), '> Why?\n\n');
        expect(mergeAskDraft('Hello', '> Why?\n\n'), 'Hello\n\n> Why?\n\n');
        expect(mergeAskDraft('> Why?', '> Why?\n\n'), '> Why?');
      },
    );

    test('buzz://olympus/ask is the master shortcut link', () {
      expect(
        parseBuzzDeepLink(Uri.parse('buzz://olympus/ask')),
        const AskMasterDeepLink(),
      );
      expect(parseBuzzDeepLink(Uri.parse('buzz://olympus/ask?x=1')), isNull);
    });
  });

  group('Olympus change requests', () {
    final agent = OlympusChangeTarget(
      operator: operatorKey,
      workspace: 'dev',
      agent: 'proof',
    );

    test('suspend names the operator, workspace, agent, and action', () {
      final request = buildOlympusChangeRequest(
        agent,
        const OlympusChange.suspend(),
      );
      expect(request.tags, [
        ['p', operatorKey],
        ['workspace', 'dev'],
        ['agent', 'proof'],
        ['action', 'suspend'],
      ]);
      expect(jsonDecode(request.content), {
        'v': 1,
        'action': 'suspend',
        'workspace': 'dev',
        'agent': 'proof',
      });
    });

    test('run-now targets a schedule and never an agent', () {
      final request = buildOlympusChangeRequest(
        OlympusChangeTarget(
          operator: operatorKey,
          workspace: 'ops',
          schedule: 'argus-daily',
        ),
        const OlympusChange.runNow(),
      );
      expect(request.tags, contains(equals(['schedule', 'argus-daily'])));
      expect(jsonDecode(request.content)['schedule'], 'argus-daily');
      expect(
        () => buildOlympusChangeRequest(agent, const OlympusChange.runNow()),
        throwsArgumentError,
      );
    });

    test(
      'approve sends highRisk only when confirmed; reject sends a reason',
      () {
        final proposal = snapshotOf([
          agentEvent(workspace: 'dev', name: 'proof'),
          proposalEvent(highRisk: ['master agent']),
        ]).proposals.single;
        final target = OlympusChangeTarget(
          operator: operatorKey,
          workspace: 'dev',
        );
        final approve = buildOlympusChangeRequest(
          target,
          OlympusChange.approve(proposal, highRisk: true),
        );
        expect(approve.tags, contains(equals(['proposal', proposal.name])));
        expect(jsonDecode(approve.content), {
          'v': 1,
          'action': 'approve',
          'workspace': 'dev',
          'proposal': proposal.name,
          'digest': digest,
          'highRisk': true,
        });
        final plain = OlympusChange.approve(proposal);
        expect(plain.params.containsKey('highRisk'), isFalse);
        expect(
          OlympusChange.reject(proposal, reason: '  not now ').params['reason'],
          'not now',
        );
        expect(
          OlympusChange.reject(
            proposal,
            reason: ' ',
          ).params.containsKey('reason'),
          isFalse,
        );
      },
    );

    test('a bad operator key is refused before signing', () {
      expect(
        () => buildOlympusChangeRequest(
          const OlympusChangeTarget(operator: 'x', workspace: 'dev'),
          const OlympusChange.resume(),
        ),
        throwsArgumentError,
      );
    });

    test('the result must come from the operator for this request', () {
      final event = olympusEvent(
        kind: OlympusKind.changeResult,
        d: 'unused',
        content: {'v': 1, 'status': 'refused', 'reason': 'managed by gitops'},
        extraTags: [
          ['e', 'f' * 64],
        ],
      );
      final refused = event.tags.firstWhere((tag) => tag[0] == 'status');
      refused[1] = 'refused';
      final result = parseOlympusChangeResult(
        event,
        requestId: 'f' * 64,
        operator: operatorKey,
        action: 'suspend',
      );
      expect(result?.phase, OlympusRequestPhase.refused);
      expect(result?.reason, 'managed by gitops');
      expect(
        parseOlympusChangeResult(
          event,
          requestId: '0' * 64,
          operator: operatorKey,
          action: 'suspend',
        ),
        isNull,
      );
      expect(
        parseOlympusChangeResult(
          event,
          requestId: 'f' * 64,
          operator: argusKey,
          action: 'suspend',
        ),
        isNull,
      );
    });

    test('working follows the newest turn frame', () {
      final now = DateTime.utc(2026, 11, 14, 9);
      ObserverFrame frame(String kind, int secondsAgo) => ObserverFrame(
        seq: secondsAgo,
        timestamp: now
            .subtract(Duration(seconds: secondsAgo))
            .toIso8601String(),
        kind: kind,
      );
      expect(olympusAgentWorking([frame('turn_started', 20)], now), isTrue);
      expect(
        olympusAgentWorking([
          frame('turn_started', 30),
          frame('turn_completed', 10),
        ], now),
        isFalse,
      );
      expect(olympusAgentWorking([frame('turn_started', 600)], now), isFalse);
      expect(olympusAgentWorking([], now), isFalse);
    });
  });

  test('an agent has respondTo, instructions file, and the last error', () {
    final event = agentEvent(workspace: 'dev', name: 'proof', publicKey: zeusKey);
    final content = jsonDecode(event.content) as Map<String, Object?>;
    (content['spec'] as Map<String, Object?>)['respondTo'] = [argusKey, 'x'];
    content['instructionsFile'] = {'repo': 'agents', 'path': 'dev/proof.md'};
    (content['status'] as Map<String, Object?>)['conditions'] = [
      {'type': 'Ready', 'status': 'True', 'reason': 'Available'},
      {'type': 'Online', 'status': 'False', 'reason': 'NoHeartbeat', 'message': 'no heartbeat'},
      {'type': 'Backup', 'status': 'False', 'reason': 'Failed'},
    ];
    final agent = OlympusAgent.parse(
      olympusEvent(
        kind: OlympusKind.agent,
        d: 'olympus-dev/proof',
        content: content,
        extraTags: [
          ['workspace', 'dev'],
        ],
      ),
    )!;
    expect(agent.spec.respondTo, [argusKey]);
    expect(agent.instructionsFile, 'agents/dev/proof.md');
    expect(agent.lastError, (title: 'NoHeartbeat', detail: 'no heartbeat'));
    expect(findOwnedOlympusAgent([agent], ownerKey, zeusKey.toUpperCase()), agent);
    expect(findOwnedOlympusAgent([agent], argusKey, zeusKey), isNull);
    expect(findOwnedOlympusAgent([agent], null, zeusKey), isNull);
  });
}
