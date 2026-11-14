import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/profile/user_cache_provider.dart';
import '../../shared/theme/buzz_icons.dart';
import '../../shared/theme/theme.dart';
import '../../shared/utils/string_utils.dart';
import '../../shared/widgets/app_list.dart';
import '../../shared/widgets/app_list_card.dart';
import 'olympus_agent_page.dart';
import 'olympus_provider.dart';
import 'olympus_state.dart';
import 'olympus_usage_page.dart';
import 'olympus_widgets.dart';

/// Read-only Olympus properties of an agent in its profile, for its owner.
class OlympusProfileCard extends ConsumerWidget {
  const OlympusProfileCard({required this.pubkey, super.key});
  final String pubkey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agent = ref.watch(
      olympusProvider.select(
        (s) => findOwnedOlympusAgent(s.agents, s.me, pubkey),
      ),
    );
    if (agent == null) return const SizedBox.shrink();
    final spec = agent.resolved;
    final working =
        agent.publicKey != null &&
        ref.watch(olympusWorkingAgentsProvider).contains(agent.publicKey);
    final muted = context.textTheme.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    String orNone(String value, [String none = 'None']) =>
        value.isEmpty ? none : value;
    final error = agent.lastError;
    final names = ref.watch(userCacheProvider);
    return Column(
      key: const ValueKey('olympus-profile-card'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppListCard(
          label: 'Olympus',
          horizontalPadding: 0,
          dividerIndent: Grid.xs,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Grid.xs,
                vertical: Grid.twelve,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      OlympusStateLabel(
                        state: olympusDisplayState(agent, working),
                      ),
                      if (agent.isMaster) ...[
                        const SizedBox(width: Grid.xxs),
                        const OlympusMasterMark(),
                      ],
                      const SizedBox(width: Grid.xxs),
                      Expanded(
                        child: Text(
                          switch (agent.lastActivity) {
                            final at? => 'Active ${formatOlympusAgo(at)}',
                            null => 'No activity',
                          },
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        ),
                      ),
                    ],
                  ),
                  if (error != null) ...[
                    const SizedBox(height: Grid.half),
                    Text(
                      [error.title, ?error.detail].join('\n'),
                      key: const ValueKey('olympus-profile-error'),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: agent.phase == OlympusPhase.suspended
                            ? context.colors.onSurfaceVariant
                            : olympusDanger(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            AppListRow(
              title: 'Workspace',
              value: '${agent.workspace} · ${agent.name}',
            ),
            AppListRow(
              title: 'Role',
              value: agent.isMaster ? 'Master' : 'Agent',
            ),
            AppListRow(
              title: 'Harness',
              value: orNone(spec.harness, 'Template'),
            ),
            AppListRow(title: 'Model', value: orNone(spec.model, 'Template')),
            AppListRow(title: 'Provider', value: orNone(spec.pool, 'Template')),
            AppListRow(title: 'Effort', value: spec.effort ?? 'Default'),
            AppListRow(
              title: 'Responds to',
              subtitle: spec.respondTo.isEmpty
                  ? 'Owner and scheduler only'
                  : spec.respondTo
                        .map(
                          (key) =>
                              names[key]?.displayName?.trim() ??
                              shortPubkey(key),
                        )
                        .join('\n'),
            ),
            AppListRow(
              title: 'MCP servers',
              subtitle: spec.mcpServers.isEmpty
                  ? 'None'
                  : spec.mcpServers.join(', '),
            ),
            AppListRow(
              title: 'Memory',
              value: spec.memoryBank == null
                  ? 'Off'
                  : 'Bank ${spec.memoryBank}',
            ),
            AppListRow(
              title: 'Instructions',
              subtitle:
                  agent.instructionsFile ??
                  spec.instructionsFromRepo ??
                  'In the agent',
            ),
            AppListRow(
              key: const ValueKey('olympus-profile-open'),
              icon: BuzzIcons.externalLink,
              title: 'Open in Olympus',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      OlympusAgentPage(author: agent.author, d: agent.d),
                ),
              ),
            ),
          ],
        ),
        if (agent.schedules.isNotEmpty)
          AppListCard(
            label: 'Schedules',
            horizontalPadding: 0,
            dividerIndent: Grid.xs,
            children: [
              for (final schedule in agent.schedules)
                AppListRow(
                  key: ValueKey('olympus-profile-schedule-${schedule.name}'),
                  title: schedule.name,
                  subtitle: [
                    schedule.cron ?? 'No cron',
                    if (schedule.lastRunTime case final at?)
                      'last ${formatOlympusAgo(at)}',
                  ].join(' · '),
                  value: schedule.suspend || agent.spec.suspend
                      ? 'Suspended'
                      : (schedule.lastResult ?? 'Never ran'),
                ),
            ],
          ),
        OlympusAgentUsageCard(agent: agent, horizontalPadding: 0),
      ],
    );
  }
}
