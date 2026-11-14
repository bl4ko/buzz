import 'package:buzz/features/olympus/master_agent.dart';
import 'package:buzz/features/olympus/olympus_agent_page.dart';
import 'package:buzz/features/olympus/olympus_agents_page.dart';
import 'package:buzz/features/olympus/olympus_proposals.dart';
import 'package:buzz/features/olympus/olympus_provider.dart';
import 'package:buzz/features/olympus/olympus_usage_page.dart';
import 'package:buzz/shared/agents/owned_agent_directory.dart';
import 'package:buzz/shared/profile/user_cache_provider.dart';
import 'package:buzz/shared/profile/user_profile.dart';
import 'package:buzz/shared/relay/relay.dart';
import 'package:buzz/shared/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'olympus_fixtures.dart';

class _Profiles extends UserCacheNotifier {
  @override
  Map<String, UserProfile> build() => {
    zeusKey: UserProfile(pubkey: zeusKey, displayName: 'Zeus'),
    argusKey: UserProfile(pubkey: argusKey, displayName: 'Argus'),
  };

  @override
  Future<bool> preload(List<String> pubkeys) async => true;
}

List<NostrEvent> _liveEvents() => [
  workspaceEvent('ops'),
  workspaceEvent('zeus'),
  agentEvent(
    workspace: 'zeus',
    name: 'zeus',
    role: 'master',
    publicKey: zeusKey,
    gitopsFields: ['spec.model', 'spec.secrets'],
    schedules: [
      {
        'name': 'zeus-case-monitor',
        'cron': '*/15 * * * *',
        'timeZone': 'Europe/Ljubljana',
        'suspend': false,
        'asAgent': true,
        'script': {'gitSource': 'olympus-zeus', 'path': 'case-monitor.sh'},
        'lastRunTime': '2026-11-14T08:45:00Z',
        'lastResult': 'Succeeded',
        'gitopsFields': <String>[],
      },
    ],
  ),
  agentEvent(
    workspace: 'ops',
    name: 'argus',
    publicKey: argusKey,
    phase: 'Suspended',
    suspend: true,
    gitopsFields: ['spec.model', 'spec.suspend'],
  ),
  usageEvent(
    workspace: 'zeus',
    name: 'zeus',
    day: {
      'tokens': {
        'claude-opus-5-5': {'input': 52000000, 'output': 1300000},
      },
      'turns': 41,
      'runs': 96,
    },
  ),
  proposalEvent(highRisk: ['master agent']),
];

Future<FakeOlympusNotifier> _pump(
  WidgetTester tester,
  Widget page, {
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = FakeOlympusNotifier(snapshotOf(_liveEvents()));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        olympusProvider.overrideWith(() => fake),
        olympusWorkingAgentsProvider.overrideWithValue({zeusKey}),
        masterDmChannelIdProvider.overrideWithValue(null),
        userCacheProvider.overrideWith(_Profiles.new),
        ownedAgentDirectoryProvider.overrideWith(
          (ref) async => const [
            OwnedAgentDirectoryEntry(pubkey: 'f00d', displayName: 'Scout'),
          ],
        ),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.light()
            : AppTheme.dark(),
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('the agents page lists workspaces, states, and the master', (
    tester,
  ) async {
    await _pump(tester, const OlympusAgentsPage());
    expect(find.text('zeus'), findsOneWidget);
    expect(find.text('ops · suspended'), findsNothing);
    expect(find.text('Zeus'), findsOneWidget);
    expect(find.text('Master'), findsOneWidget);
    expect(find.text('Working'), findsOneWidget);
    expect(find.text('Suspended'), findsOneWidget);
    expect(find.text('Other agents'), findsOneWidget);
    expect(find.text('Scout'), findsOneWidget);
    final proposals = find.byKey(const ValueKey('olympus-open-proposals'));
    expect(
      find.descendant(of: proposals, matching: find.text('1')),
      findsOneWidget,
    );
  });

  testWidgets('the agent page shows config, git locks, and suspends', (
    tester,
  ) async {
    final fake = await _pump(
      tester,
      OlympusAgentPage(author: operatorKey, d: 'olympus-zeus/zeus'),
    );
    expect(find.text('claude-opus-5-5'), findsOneWidget);
    expect(find.text('github-token → GH_TOKEN'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('olympus-field-spec.model')),
        matching: find.text('git'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('olympus-field-spec.effort')),
        matching: find.text('git'),
      ),
      findsNothing,
    );
    expect(find.text('53M tokens'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('olympus-agent-suspend')));
    await tester.pumpAndSettle();
    expect(find.text('Suspend Zeus?'), findsOneWidget);
    await tester.tap(find.text('Suspend').last);
    await tester.pumpAndSettle();
    final sent = fake.sent.single;
    expect(sent.change.action, 'suspend');
    expect(sent.target.agent, 'zeus');
    expect(sent.target.workspace, 'zeus');

    await tester.tap(
      find.byKey(const ValueKey('olympus-schedule-zeus-case-monitor')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('olympus-schedule-run-now')));
    await tester.pumpAndSettle();
    expect(fake.sent.last.change.action, 'run-now');
    expect(fake.sent.last.target.schedule, 'zeus-case-monitor');
    expect(fake.sent.last.target.agent, isNull);
  });

  testWidgets('suspend is locked when git owns it', (tester) async {
    await _pump(
      tester,
      OlympusAgentPage(author: operatorKey, d: 'olympus-ops/argus'),
    );
    expect(find.byKey(const ValueKey('olympus-agent-suspend')), findsNothing);
    expect(find.text('Suspend is set in gitops-home'), findsOneWidget);
  });

  testWidgets('a high-risk approval needs a second confirmation', (
    tester,
  ) async {
    final fake = await _pump(tester, const OlympusProposalsPage());
    expect(find.text('High risk: master agent'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('olympus-proposal-approve')));
    await tester.pumpAndSettle();
    expect(find.text('Approve a high-risk change?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fake.sent, isEmpty);

    await tester.tap(find.byKey(const ValueKey('olympus-proposal-approve')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve').last);
    await tester.pumpAndSettle();
    expect(fake.sent.single.change.action, 'approve');
    expect(fake.sent.single.change.params['highRisk'], isTrue);
    expect(fake.sent.single.target.agent, isNull);
  });

  testWidgets('reject sends the reason back', (tester) async {
    final fake = await _pump(tester, const OlympusProposalsPage());
    await tester.tap(find.byKey(const ValueKey('olympus-proposal-reject')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('olympus-reject-reason')),
      'Proof runs the e2e checks today.',
    );
    await tester.tap(find.byKey(const ValueKey('olympus-reject-confirm')));
    await tester.pumpAndSettle();
    expect(fake.sent.single.change.action, 'reject');
    expect(
      fake.sent.single.change.params['reason'],
      'Proof runs the e2e checks today.',
    );
  });

  testWidgets('the Zeus DM shows the proposal card above the composer', (
    tester,
  ) async {
    await _pump(tester, Scaffold(body: OlympusDmProposals(peer: zeusKey)));
    expect(find.byKey(const ValueKey('olympus-dm-proposals')), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    await _pump(tester, Scaffold(body: OlympusDmProposals(peer: argusKey)));
    expect(find.byKey(const ValueKey('olympus-dm-proposals')), findsNothing);
  });

  testWidgets('usage shows tokens per agent in light and dark', (tester) async {
    for (final brightness in Brightness.values) {
      await _pump(tester, const OlympusUsagePage(), brightness: brightness);
      expect(find.text('53M'), findsWidgets);
      expect(find.textContaining('USD'), findsNothing);
      expect(find.textContaining(r'$'), findsNothing);
    }
  });

  testWidgets('the master row pins Zeus with its proposal count', (
    tester,
  ) async {
    await _pump(tester, const Scaffold(body: MasterAgentRow()));
    expect(find.text('Zeus'), findsOneWidget);
    expect(find.text('Working…'), findsOneWidget);
    final badge = tester.getTopRight(find.text('1'));
    expect(badge.dx, greaterThan(330));
  });
}
