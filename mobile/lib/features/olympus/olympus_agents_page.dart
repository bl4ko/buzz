import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/agents/owned_agent_directory.dart';
import '../../shared/theme/buzz_icons.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/agent_navigation_icon.dart';
import '../../shared/widgets/app_list.dart';
import '../../shared/widgets/app_list_card.dart';
import '../../shared/widgets/avatar_image.dart';
import '../../shared/widgets/frosted_app_bar.dart';
import '../../shared/widgets/frosted_scaffold.dart';
import '../../shared/widgets/navigation_button_surface.dart';
import '../agents/agents_page.dart';
import 'master_agent.dart';
import 'olympus_agent_page.dart';
import 'olympus_proposals.dart';
import 'olympus_provider.dart';
import 'olympus_state.dart';
import 'olympus_usage_page.dart';
import 'olympus_widgets.dart';

void showOlympusAgents(BuildContext context) {
  unawaited(
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const OlympusAgentsPage())),
  );
}

/// The round agents button on Messages, with the open proposal count.
class OlympusAgentsButton extends ConsumerWidget {
  const OlympusAgentsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(olympusPendingCountProvider);
    return NavigationButtonSurface(
      child: SizedBox.square(
        dimension: 56,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: IconButton(
                key: const ValueKey('olympus-agents-button'),
                tooltip: pending > 0
                    ? 'Agents, $pending proposals waiting'
                    : 'Agents',
                onPressed: () {
                  unawaited(HapticFeedback.lightImpact());
                  showOlympusAgents(context);
                },
                icon: AgentNavigationIcon(
                  size: 24,
                  color: context.colors.onSurface,
                ),
              ),
            ),
            if (pending > 0)
              Positioned(
                top: 4,
                right: 4,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: OlympusCountBadge(count: pending),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class OlympusAgentsPage extends ConsumerWidget {
  const OlympusAgentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(olympusProvider);
    final working = ref.watch(olympusWorkingAgentsProvider);
    final pending = ref.watch(olympusPendingCountProvider);
    final olympusKeys = {for (final agent in snapshot.agents) ?agent.publicKey};
    final local = [
      for (final entry
          in ref.watch(ownedAgentDirectoryProvider).asData?.value ??
              const <OwnedAgentDirectoryEntry>[])
        if (!olympusKeys.contains(entry.pubkey)) entry,
    ];
    final topHeight = frostedAppBarHeight(
      context,
      nativeLargeTitle: true,
      bottomHeight: Grid.xxs,
    );
    void open(Widget page) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));

    return FrostedScaffold(
      useUtilitySurfaceTheme: true,
      appBar: FrostedAppBar(
        nativeTitle: 'Agents',
        nativeLargeTitle: true,
        automaticallyImplyLeading: false,
        nativeLeading: IosNavigationAction(
          label: 'Close agents',
          symbol: 'xmark',
          onPressed: () => Navigator.of(context).pop(),
        ),
        leading: IconButton(
          tooltip: 'Close agents',
          icon: const Icon(BuzzIcons.x),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Agents'),
        horizontalInset: Grid.gutter,
        bottomHeight: Grid.xxs,
        bottom: const SizedBox.expand(),
      ),
      body: ListView(
        padding: EdgeInsets.only(
          top: topHeight,
          bottom: MediaQuery.paddingOf(context).bottom + Grid.md,
        ),
        children: [
          AppListCard(
            children: [
              AppListRow(
                key: const ValueKey('olympus-open-proposals'),
                icon: BuzzIcons.shieldCheck,
                title: 'Proposals',
                value: pending > 0 ? null : 'None open',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (pending > 0) OlympusCountBadge(count: pending),
                    const SizedBox(width: Grid.half),
                    const _Chevron(),
                  ],
                ),
                onTap: () => open(const OlympusProposalsPage()),
              ),
              AppListRow(
                key: const ValueKey('olympus-open-usage'),
                icon: BuzzIcons.activity,
                title: 'Usage',
                value: 'Tokens',
                trailing: const _Chevron(),
                onTap: () => open(const OlympusUsagePage()),
              ),
            ],
          ),
          if (snapshot.groups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Grid.gutter,
                vertical: Grid.md,
              ),
              child: snapshot.loaded
                  ? Text(
                      'No Olympus agents. Hephaestus shows the agents that '
                      'you own in this community.',
                      textAlign: TextAlign.center,
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    )
                  : const Center(
                      child: SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
            ),
          for (final group in snapshot.groups)
            AppListCard(
              key: ValueKey('olympus-workspace-${group.name}'),
              label: group.workspace?.suspend == true
                  ? '${group.name} · suspended'
                  : group.name,
              dividerIndent: Grid.xs + 40 + Grid.xs,
              children: [
                for (final agent in group.agents)
                  _AgentRow(
                    agent: agent,
                    working:
                        agent.publicKey != null &&
                        working.contains(agent.publicKey),
                    onTap: () => open(
                      OlympusAgentPage(author: agent.author, d: agent.d),
                    ),
                  ),
              ],
            ),
          if (local.isNotEmpty)
            AppListCard(
              label: 'Other agents',
              dividerIndent: Grid.xs + 40 + Grid.xs,
              children: [
                for (final entry in local)
                  AppListRowRaw(
                    leading: AvatarImage(
                      imageUrl: entry.avatarUrl,
                      radius: 20,
                      isAgent: true,
                      backgroundColor: context.controlSurface,
                      fallback: Text(
                        (entry.displayName ?? '?').characters.first,
                      ),
                    ),
                    title: Text(
                      entry.displayName ?? 'Agent',
                      style: context.textTheme.bodyLarge,
                    ),
                    subtitle: entry.model == null
                        ? null
                        : Text(
                            entry.model!,
                            style: context.textTheme.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                    trailing: const _Chevron(),
                    onTap: () => openAgentDm(context, ref, entry.pubkey),
                  ),
                AppListRow(
                  icon: BuzzIcons.settings,
                  title: 'Manage other agents',
                  trailing: const _Chevron(),
                  onTap: () => unawaited(showAgents(context)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) =>
      Icon(BuzzIcons.chevronRight, size: 18, color: context.tertiaryTextColor);
}

class _AgentRow extends ConsumerWidget {
  const _AgentRow({
    required this.agent,
    required this.working,
    required this.onTap,
  });

  final OlympusAgent agent;
  final bool working;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = olympusAgentLabel(ref, agent);
    return AppListRowRaw(
      key: ValueKey('olympus-agent-${agent.d}'),
      verticalPadding: Grid.twelve,
      leading: OlympusAgentAvatar(agent: agent, size: 40),
      title: Row(
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (agent.isMaster) ...[
            const SizedBox(width: Grid.xxs - 2),
            const OlympusMasterMark(),
          ],
        ],
      ),
      subtitle: Row(
        children: [
          OlympusStateLabel(state: olympusDisplayState(agent, working)),
          Expanded(
            child: Text(
              [
                agent.resolved.model,
                if (agent.schedules.isNotEmpty)
                  '${agent.schedules.length} schedule${agent.schedules.length == 1 ? '' : 's'}',
              ].where((part) => part.isNotEmpty).map((p) => ' · $p').join(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      trailing: const _Chevron(),
      onTap: onTap,
    );
  }
}
