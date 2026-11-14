import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/theme/buzz_icons.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/app_list.dart';
import '../../shared/widgets/app_list_card.dart';
import '../../shared/widgets/confirmation_dialog.dart';
import '../../shared/widgets/frosted_app_bar.dart';
import '../../shared/widgets/frosted_scaffold.dart';
import '../../shared/widgets/modal_presentation.dart';
import '../../shared/widgets/sheet_action_section.dart';
import 'master_agent.dart';
import 'olympus_provider.dart';
import 'olympus_state.dart';
import 'olympus_usage_page.dart';
import 'olympus_widgets.dart';

String olympusAgentRequestKey(OlympusAgent agent) =>
    '${agent.workspace}/${agent.name}';

String olympusScheduleRequestKey(
  OlympusAgent agent,
  OlympusSchedule schedule,
) => '${agent.workspace}#schedule/${schedule.name}';

class OlympusAgentPage extends ConsumerWidget {
  const OlympusAgentPage({required this.author, required this.d, super.key});
  final String author;
  final String d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(olympusProvider);
    final agent = snapshot.agent(author, d);
    final topHeight = frostedAppBarHeight(context, bottomHeight: Grid.xxs);
    final title = agent == null ? 'Agent' : olympusAgentLabel(ref, agent);
    return FrostedScaffold(
      useUtilitySurfaceTheme: true,
      appBar: FrostedAppBar(
        nativeTitle: title,
        title: Text(title),
        horizontalInset: Grid.gutter,
        bottomHeight: Grid.xxs,
        bottom: const SizedBox.expand(),
      ),
      body: agent == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(Grid.gutter),
                child: Text(
                  snapshot.loaded
                      ? 'Hephaestus publishes no state for $d. It was deleted, '
                            'or this identity is not its owner.'
                      : 'Loading…',
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : ListView(
              padding: EdgeInsets.only(
                top: topHeight,
                bottom: MediaQuery.paddingOf(context).bottom + Grid.md,
              ),
              children: [
                _Header(agent: agent),
                _Status(agent: agent),
                _Config(agent: agent),
                if (agent.schedules.isNotEmpty) _Schedules(agent: agent),
                _Access(agent: agent),
                OlympusAgentUsageCard(agent: agent),
              ],
            ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.agent});
  final OlympusAgent agent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = olympusAgentRequestKey(agent);
    final request = ref.watch(olympusProvider.select((s) => s.requests[key]));
    final pending = request?.phase == OlympusRequestPhase.pending;
    final working =
        agent.publicKey != null &&
        ref.watch(olympusWorkingAgentsProvider).contains(agent.publicKey);
    final suspended = agent.spec.suspend;
    final locked = olympusFieldLocked(
      managedBy: agent.managedBy,
      gitopsFields: agent.gitopsFields,
      path: 'spec.suspend',
    );
    final label = olympusAgentLabel(ref, agent);

    Future<void> toggleSuspend() async {
      if (!suspended &&
          !await showDestructiveConfirmation(
            context: context,
            title: 'Suspend $label?',
            message:
                'Hephaestus stops ${agent.workspace}/${agent.name} and its '
                'schedules until you resume it.',
            confirmLabel: 'Suspend',
          )) {
        return;
      }
      unawaited(HapticFeedback.mediumImpact());
      await ref
          .read(olympusProvider.notifier)
          .submit(
            key,
            OlympusChangeTarget(
              operator: agent.author,
              workspace: agent.workspace,
              agent: agent.name,
            ),
            suspended
                ? const OlympusChange.resume()
                : const OlympusChange.suspend(),
          );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Grid.gutter,
        Grid.xs,
        Grid.gutter,
        Grid.xxs,
      ),
      child: Column(
        children: [
          OlympusAgentAvatar(agent: agent, size: 76),
          const SizedBox(height: Grid.twelve),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: context.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (agent.isMaster) ...[
                const SizedBox(width: Grid.xxs),
                const OlympusMasterMark(),
              ],
            ],
          ),
          const SizedBox(height: Grid.half),
          Text(
            '${agent.workspace}/${agent.name}',
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Menlo'],
            ),
          ),
          const SizedBox(height: Grid.xxs),
          OlympusStateLabel(state: olympusDisplayState(agent, working)),
          if (agent.spec.about case final about?) ...[
            const SizedBox(height: Grid.xxs),
            Text(
              about,
              textAlign: TextAlign.center,
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: Grid.xs),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: Grid.xxs,
            runSpacing: Grid.xxs,
            children: [
              OlympusPillButton(
                key: const ValueKey('olympus-agent-message'),
                label: 'Message',
                icon: BuzzIcons.messageCircle,
                prominent: true,
                onPressed: agent.publicKey == null
                    ? null
                    : () => openAgentDm(context, ref, agent.publicKey!),
              ),
              if (!locked)
                OlympusPillButton(
                  key: const ValueKey('olympus-agent-suspend'),
                  label: suspended ? 'Resume' : 'Suspend',
                  icon: suspended ? BuzzIcons.play : BuzzIcons.pause,
                  onPressed: pending ? null : toggleSuspend,
                ),
            ],
          ),
          if (locked) ...[
            const SizedBox(height: Grid.xxs),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const OlympusGitLock(),
                const SizedBox(width: Grid.half),
                Flexible(
                  child: Text(
                    'Suspend is set in gitops-home',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (request != null) ...[
            const SizedBox(height: Grid.twelve),
            OlympusRequestLine(
              state: request,
              onDismiss: () =>
                  ref.read(olympusProvider.notifier).clearRequest(key),
            ),
          ],
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.agent});
  final OlympusAgent agent;

  @override
  Widget build(BuildContext context) => AppListCard(
    label: 'Status',
    dividerIndent: Grid.xs,
    children: [
      AppListRow(title: 'Phase', value: _phaseName(agent.phase)),
      if (agent.reason != null &&
          agent.phase != OlympusPhase.online &&
          agent.reason != _phaseName(agent.phase))
        AppListRow(
          title: 'Reason',
          subtitle: agent.reason,
          subtitleMaxLines: 4,
        ),
      if (agent.lastActivity case final at?)
        AppListRow(title: 'Last activity', value: formatOlympusAgo(at)),
      if (agent.managedBy == 'gitops')
        const AppListRow(title: 'Managed by', value: 'gitops-home'),
    ],
  );
}

String _phaseName(OlympusPhase phase) =>
    '${phase.name[0].toUpperCase()}${phase.name.substring(1)}';

class _LockedRow extends StatelessWidget {
  const _LockedRow({
    required this.agent,
    required this.title,
    required this.path,
    required this.value,
  });

  final OlympusAgent agent;
  final String title;
  final String path;
  final String value;

  @override
  Widget build(BuildContext context) {
    final locked = olympusFieldLocked(
      managedBy: agent.managedBy,
      gitopsFields: agent.gitopsFields,
      path: path,
    );
    return AppListRow(
      key: ValueKey('olympus-field-$path'),
      title: title,
      value: value,
      trailing: locked ? const OlympusGitLock() : null,
    );
  }
}

class _Config extends StatelessWidget {
  const _Config({required this.agent});
  final OlympusAgent agent;

  @override
  Widget build(BuildContext context) {
    final spec = agent.resolved;
    return AppListCard(
      label: 'Configuration',
      dividerIndent: Grid.xs,
      children: [
        _LockedRow(
          agent: agent,
          title: 'Model',
          path: 'spec.model',
          value: spec.model.isEmpty ? 'Template' : spec.model,
        ),
        _LockedRow(
          agent: agent,
          title: 'Effort',
          path: 'spec.effort',
          value: spec.effort ?? 'Default',
        ),
        _LockedRow(
          agent: agent,
          title: 'Harness',
          path: 'spec.harness',
          value: spec.harness.isEmpty ? 'Template' : spec.harness,
        ),
        _LockedRow(
          agent: agent,
          title: 'Model provider',
          path: 'spec.pool',
          value: spec.pool.isEmpty ? 'Template' : spec.pool,
        ),
        if (agent.spec.template case final template?)
          _LockedRow(
            agent: agent,
            title: 'Template',
            path: 'spec.template',
            value: template,
          ),
        _LockedRow(
          agent: agent,
          title: 'Memory',
          path: 'spec.memory',
          value: spec.memoryBank ?? 'None',
        ),
        _LockedRow(
          agent: agent,
          title: 'Instructions',
          path: 'spec.instructions',
          value: spec.instructionsFromRepo ?? 'In the agent',
        ),
      ],
    );
  }
}

class _Access extends StatelessWidget {
  const _Access({required this.agent});
  final OlympusAgent agent;

  @override
  Widget build(BuildContext context) {
    final spec = agent.resolved;
    String list(Iterable<String> values) =>
        values.isEmpty ? 'None' : values.join('\n');
    Widget row(String title, String path, String text) {
      final locked = olympusFieldLocked(
        managedBy: agent.managedBy,
        gitopsFields: agent.gitopsFields,
        path: path,
      );
      return AppListRow(
        key: ValueKey('olympus-field-$path'),
        title: title,
        subtitle: text,
        subtitleStyle: context.textTheme.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Menlo'],
        ),
        trailing: locked ? const OlympusGitLock() : null,
      );
    }

    return AppListCard(
      label: 'Access',
      dividerIndent: Grid.xs,
      children: [
        row(
          'Egress${agent.egressMode == null ? '' : ' · ${agent.egressMode}'}',
          'spec.egress',
          list(spec.egress.map((rule) => rule.label)),
        ),
        row(
          'Secrets',
          'spec.secrets',
          list(
            spec.secrets.map(
              (secret) => secret.env == null
                  ? secret.name
                  : '${secret.name} → ${secret.env}',
            ),
          ),
        ),
        row('MCP servers', 'spec.mcpServers', list(spec.mcpServers)),
        if (spec.gitSources.isNotEmpty)
          row('Git', 'spec.gitSources', list(spec.gitSources)),
        if (spec.skills.isNotEmpty)
          row('Skills', 'spec.skills', list(spec.skills)),
        if (spec.kubernetesRole case final role?)
          row('Kubernetes role', 'spec.kubernetesRole', role),
      ],
    );
  }
}

class _Schedules extends ConsumerWidget {
  const _Schedules({required this.agent});
  final OlympusAgent agent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(olympusProvider.select((s) => s.requests));
    return AppListCard(
      label: 'Schedules',
      dividerIndent: Grid.xs,
      children: [
        for (final schedule in agent.schedules)
          _ScheduleRow(
            agent: agent,
            schedule: schedule,
            request: requests[olympusScheduleRequestKey(agent, schedule)],
          ),
      ],
    );
  }
}

class _ScheduleRow extends ConsumerWidget {
  const _ScheduleRow({
    required this.agent,
    required this.schedule,
    required this.request,
  });

  final OlympusAgent agent;
  final OlympusSchedule schedule;
  final OlympusRequestState? request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suspended = schedule.suspend || agent.spec.suspend;
    final failed = schedule.lastResult == 'Failed';
    final lastRun = schedule.lastRunTime;
    final pending = request?.phase == OlympusRequestPhase.pending;
    return InkWell(
      key: ValueKey('olympus-schedule-${schedule.name}'),
      onTap: schedule.supportsActions && !pending
          ? () => _showScheduleActions(context, ref, agent, schedule)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Grid.xs,
          vertical: Grid.twelve,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    schedule.name,
                    style: context.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (suspended)
                  Text(
                    schedule.suspend ? 'Suspended' : 'Agent suspended',
                    style: context.textTheme.labelMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  )
                else if (schedule.lastResult != null)
                  Text(
                    schedule.lastResult!,
                    style: context.textTheme.labelMedium?.copyWith(
                      color: failed
                          ? olympusDanger(context)
                          : context.appColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (schedule.supportsActions) ...[
                  const SizedBox(width: Grid.half),
                  Icon(
                    BuzzIcons.ellipsis,
                    size: 18,
                    color: context.tertiaryTextColor,
                  ),
                ],
              ],
            ),
            const SizedBox(height: Grid.quarter),
            Text(
              [
                schedule.cron ?? 'No cron',
                schedule.timeZone ?? 'UTC',
                schedule.mode,
                if (lastRun != null) 'last ${formatOlympusAgo(lastRun)}',
              ].join(' · '),
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            if (request != null) ...[
              const SizedBox(height: Grid.xxs),
              OlympusRequestLine(
                state: request,
                onDismiss: () => ref
                    .read(olympusProvider.notifier)
                    .clearRequest(olympusScheduleRequestKey(agent, schedule)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

void _showScheduleActions(
  BuildContext context,
  WidgetRef ref,
  OlympusAgent agent,
  OlympusSchedule schedule,
) {
  final locked = olympusFieldLocked(
    managedBy: agent.managedBy,
    gitopsFields: schedule.gitopsFields,
    path: 'spec.suspend',
  );
  final suspended = schedule.suspend || agent.spec.suspend;
  void send(OlympusChange change) {
    unawaited(HapticFeedback.mediumImpact());
    unawaited(
      ref
          .read(olympusProvider.notifier)
          .submit(
            olympusScheduleRequestKey(agent, schedule),
            OlympusChangeTarget(
              operator: agent.author,
              workspace: agent.workspace,
              schedule: schedule.name,
            ),
            change,
          ),
    );
  }

  unawaited(
    showBuzzModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      title: schedule.name,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Grid.gutter,
            0,
            Grid.gutter,
            Grid.xs,
          ),
          child: SheetActionSection(
            children: [
              ListTile(
                key: const ValueKey('olympus-schedule-run-now'),
                enabled: !suspended,
                leading: const Icon(BuzzIcons.play),
                title: const Text('Run now'),
                subtitle: suspended ? const Text('Resume it first.') : null,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  send(const OlympusChange.runNow());
                },
              ),
              if (locked)
                const ListTile(
                  leading: Icon(BuzzIcons.lock),
                  title: Text('Suspend is set in gitops-home'),
                )
              else
                ListTile(
                  key: const ValueKey('olympus-schedule-suspend'),
                  leading: Icon(
                    schedule.suspend ? BuzzIcons.play : BuzzIcons.pause,
                  ),
                  title: Text(
                    schedule.suspend ? 'Resume schedule' : 'Suspend schedule',
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    send(
                      schedule.suspend
                          ? const OlympusChange.resumeSchedule()
                          : const OlympusChange.suspendSchedule(),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
