import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/theme/theme.dart';
import '../../shared/widgets/app_list.dart';
import '../../shared/widgets/app_list_card.dart';
import '../../shared/widgets/frosted_app_bar.dart';
import '../../shared/widgets/frosted_scaffold.dart';
import 'olympus_proposals.dart';
import 'olympus_provider.dart';
import 'olympus_state.dart';
import 'olympus_widgets.dart';

const olympusUsageWindows = ['24h', '7d'];

String _windowLabel(String window) =>
    window == '24h' ? 'Last 24 hours' : 'Last 7 days';

class OlympusUsagePage extends HookConsumerWidget {
  const OlympusUsagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = useState(0);
    final window = olympusUsageWindows[selected.value];
    final snapshot = ref.watch(olympusProvider);
    final rows = [
      for (final agent in snapshot.agents)
        (agent: agent, usage: snapshot.usageFor(agent)?.windows[window]),
    ]..sort((a, b) => (b.usage?.tokens ?? 0).compareTo(a.usage?.tokens ?? 0));
    final total = rows.fold(0, (sum, row) => sum + (row.usage?.tokens ?? 0));
    final largest = rows.isEmpty ? 0 : rows.first.usage?.tokens ?? 0;
    final at = snapshot.usage.values.fold<int?>(
      null,
      (latest, usage) =>
          latest == null || usage.at > latest ? usage.at : latest,
    );
    final topHeight = frostedAppBarHeight(
      context,
      nativeLargeTitle: true,
      bottomHeight: Grid.xxs,
    );
    return FrostedScaffold(
      useUtilitySurfaceTheme: true,
      appBar: const FrostedAppBar(
        nativeTitle: 'Usage',
        nativeLargeTitle: true,
        title: Text('Usage'),
        horizontalInset: Grid.gutter,
        bottomHeight: Grid.xxs,
        bottom: SizedBox.expand(),
      ),
      body: ListView(
        padding: EdgeInsets.only(
          top: topHeight + Grid.xxs,
          bottom: MediaQuery.paddingOf(context).bottom + Grid.md,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Grid.gutter),
            child: OlympusSegments(
              items: const ['24 hours', '7 days'],
              selected: selected.value,
              onChanged: (index) => selected.value = index,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Grid.gutter,
              Grid.sm,
              Grid.gutter,
              Grid.xxs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatCompactCount(total),
                  key: const ValueKey('olympus-usage-total'),
                  style: context.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'tokens · ${_windowLabel(window).toLowerCase()}'
                  '${at == null ? '' : ' · updated ${formatOlympusAgo(DateTime.fromMillisecondsSinceEpoch(at * 1000))}'}',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          AppListCard(
            label: 'By agent',
            dividerIndent: Grid.xs + 32 + Grid.xs,
            children: [
              if (rows.isEmpty)
                AppListRow(
                  title: snapshot.loaded ? 'No usage yet' : 'Loading…',
                ),
              for (final row in rows)
                AppListRowRaw(
                  key: ValueKey('olympus-usage-${row.agent.d}'),
                  verticalPadding: Grid.twelve,
                  leading: OlympusAgentAvatar(agent: row.agent, size: 32),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          olympusAgentLabel(ref, row.agent),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        row.usage == null
                            ? 'No data'
                            : formatCompactCount(row.usage!.tokens),
                        style: context.textTheme.bodyLarge?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: row.usage == null
                              ? context.colors.onSurfaceVariant
                              : null,
                        ),
                      ),
                    ],
                  ),
                  subtitle: _UsageDetail(
                    usage: row.usage,
                    fraction: largest == 0
                        ? 0
                        : (row.usage?.tokens ?? 0) / largest,
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Grid.gutter),
            child: Text(
              'Tokens come from the agent telemetry. Hephaestus updates them '
              'every 10 minutes.',
              style: context.textTheme.bodySmall?.copyWith(
                color: context.tertiaryTextColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageDetail extends StatelessWidget {
  const _UsageDetail({required this.usage, required this.fraction});
  final OlympusUsageWindow? usage;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final window = usage;
    final style = context.textTheme.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Grid.half),
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.full),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 4,
            color: context.colors.primary,
            backgroundColor: context.colors.onSurface.withValues(alpha: 0.08),
          ),
        ),
        if (window != null) ...[
          const SizedBox(height: Grid.half),
          Text(
            [
              for (final entry in window.models.take(2))
                '${entry.model} ${formatCompactCount(entry.tokens)}',
              '${window.turns} turns',
              if (window.runs > 0)
                '${window.runs} runs${window.failedRuns > 0 ? ', ${window.failedRuns} failed' : ''}',
            ].join(' · '),
            style: style,
          ),
        ],
      ],
    );
  }
}

/// Token usage of one agent, for its page.
class OlympusAgentUsageCard extends ConsumerWidget {
  const OlympusAgentUsageCard({
    required this.agent,
    this.horizontalPadding = Grid.gutter,
    super.key,
  });
  final OlympusAgent agent;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(olympusProvider.select((s) => s.usageFor(agent)));
    return AppListCard(
      label: 'Usage',
      horizontalPadding: horizontalPadding,
      dividerIndent: Grid.xs,
      children: [
        if (usage == null) const AppListRow(title: 'No usage data yet'),
        for (final window in olympusUsageWindows)
          if (usage?.windows[window] case final data?)
            AppListRow(
              key: ValueKey('olympus-agent-usage-$window'),
              title: _windowLabel(window),
              value: '${formatCompactCount(data.tokens)} tokens',
              subtitle: [
                for (final entry in data.models)
                  '${entry.model}: ${formatCompactCount(entry.tokens)}',
                '${data.turns} turns · ${data.runs} runs'
                    '${data.failedRuns > 0 ? ' (${data.failedRuns} failed)' : ''}'
                    '${data.apiErrors > 0 ? ' · ${data.apiErrors} API errors' : ''}',
              ].join('\n'),
            ),
      ],
    );
  }
}
