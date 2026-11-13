import * as React from "react";
import { Check, CircleAlert, Gauge, Minus } from "lucide-react";

import type { OlympusWorkspaceGroup } from "@/features/agents/lib/olympusAgents";
import {
  formatCompactCount,
  formatShare,
  OLYMPUS_USAGE_WINDOWS,
  type OlympusAccountUsage,
  type OlympusAgentUsage,
  type OlympusModelTokens,
  type OlympusUsageLastRun,
  type OlympusUsageWindowKey,
  olympusUsageModelOrder,
  summarizeOlympusUsage,
  windowModelTokens,
} from "@/features/agents/lib/olympusUsage";
import { useOlympusUsage } from "@/features/agents/useOlympusUsage";
import { useUsersBatchQuery } from "@/features/profile/hooks";
import { ProfileAvatar } from "@/features/profile/ui/ProfileAvatar";
import { cn } from "@/shared/lib/cn";
import { useNow } from "@/shared/lib/useNow";
import { SegmentedControl } from "@/shared/ui/segmented-control";
import { Spinner } from "@/shared/ui/spinner";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/shared/ui/tooltip";

const MODEL_SWATCHES = [
  "bg-[#2a78d6] dark:bg-[#3987e5]",
  "bg-[#eb6834] dark:bg-[#d95926]",
  "bg-[#1baf7a] dark:bg-[#199e70]",
  "bg-[#eda100] dark:bg-[#c98500]",
  "bg-[#e87ba4] dark:bg-[#d55181]",
] as const;
const OTHER_SWATCH = "bg-muted-foreground/40";
const OTHER_MODEL = "Other";

const WINDOW_OPTIONS = [
  { value: "24h", label: "24 hours" },
  { value: "7d", label: "7 days" },
] as const satisfies readonly {
  value: OlympusUsageWindowKey;
  label: string;
}[];

const EMPTY_REASON =
  "No usage from this relay. The operator publishes kind 30193 to the owner key.";

type ModelPalette = (model: string) => { label: string; swatch: string };

function useModelPalette(agents: readonly OlympusAgentUsage[]): ModelPalette {
  const order = React.useMemo(() => olympusUsageModelOrder(agents), [agents]);
  return React.useCallback(
    (model: string) => {
      const index = order.indexOf(model);
      return index >= 0 && index < MODEL_SWATCHES.length
        ? { label: model, swatch: MODEL_SWATCHES[index] }
        : { label: OTHER_MODEL, swatch: OTHER_SWATCH };
    },
    [order],
  );
}

function foldModels(
  models: readonly OlympusModelTokens[],
  palette: ModelPalette,
): { label: string; swatch: string; tokens: number }[] {
  const folded = new Map<
    string,
    { label: string; swatch: string; tokens: number }
  >();
  for (const entry of models) {
    const { label, swatch } = palette(entry.model);
    const current = folded.get(label);
    if (current) current.tokens += entry.tokens;
    else folded.set(label, { label, swatch, tokens: entry.tokens });
  }
  return [...folded.values()];
}

function relative(atSeconds: number, nowMs: number) {
  const seconds = Math.max(0, Math.floor(nowMs / 1_000) - atSeconds);
  if (seconds < 60) return "just now";
  if (seconds < 3_600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86_400) return `${Math.floor(seconds / 3_600)}h ago`;
  return `${Math.floor(seconds / 86_400)}d ago`;
}

function formatExact(value: number) {
  return Math.round(value).toLocaleString();
}

function ModelBar({
  className,
  models,
  palette,
  scale,
}: {
  className?: string;
  models: readonly OlympusModelTokens[];
  palette: ModelPalette;
  scale: number;
}) {
  const parts = foldModels(models, palette);
  const total = parts.reduce((sum, part) => sum + part.tokens, 0);
  if (total === 0 || scale <= 0) {
    return <div className={cn("h-1.5 rounded-full bg-muted/60", className)} />;
  }
  const label = parts
    .map((part) => `${part.label}: ${formatCompactCount(part.tokens)}`)
    .join(", ");
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <div
          aria-label={label}
          className={cn("flex h-1.5 rounded-full bg-muted/60", className)}
          role="img"
        >
          <div
            className="flex h-full gap-[2px]"
            style={{ width: `${Math.max(2, (total / scale) * 100)}%` }}
          >
            {parts.map((part) => (
              <div
                className={cn("h-full min-w-[3px] rounded-full", part.swatch)}
                key={part.label}
                style={{ flexGrow: part.tokens, flexBasis: 0 }}
              />
            ))}
          </div>
        </div>
      </TooltipTrigger>
      <TooltipContent className="space-y-1" side="top">
        {parts.map((part) => (
          <div className="flex items-center gap-2" key={part.label}>
            <span
              aria-hidden
              className={cn("h-2 w-2 rounded-full", part.swatch)}
            />
            <span className="min-w-0 flex-1 truncate">{part.label}</span>
            <span className="tabular-nums">{formatExact(part.tokens)}</span>
          </div>
        ))}
      </TooltipContent>
    </Tooltip>
  );
}

function ModelLegend({
  agents,
  palette,
}: {
  agents: readonly OlympusAgentUsage[];
  palette: ModelPalette;
}) {
  const labels = React.useMemo(() => {
    const seen = new Map<string, string>();
    for (const model of olympusUsageModelOrder(agents)) {
      const { label, swatch } = palette(model);
      if (!seen.has(label)) seen.set(label, swatch);
    }
    return [...seen.entries()];
  }, [agents, palette]);
  if (labels.length === 0) return null;
  return (
    <ul
      aria-label="Models"
      className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground"
    >
      {labels.map(([label, swatch]) => (
        <li className="flex items-center gap-1.5" key={label}>
          <span aria-hidden className={cn("h-2 w-2 rounded-full", swatch)} />
          {label}
        </li>
      ))}
    </ul>
  );
}

function FailedRuns({ count }: { count: number }) {
  if (count === 0) {
    return <span className="text-muted-foreground">0</span>;
  }
  return (
    <span className="inline-flex items-center gap-1 font-medium text-destructive">
      <CircleAlert aria-hidden className="h-3.5 w-3.5" />
      {count}
      <span className="sr-only"> failed</span>
    </span>
  );
}

const RUN_RESULTS = {
  succeeded: {
    Icon: Check,
    className: "text-emerald-700 dark:text-emerald-300",
  },
  failed: { Icon: CircleAlert, className: "text-destructive" },
  nowork: { Icon: Minus, className: "text-muted-foreground" },
} as const;

function LastRun({
  lastRun,
  nowMs,
}: {
  lastRun: OlympusUsageLastRun | null;
  nowMs: number;
}) {
  if (!lastRun) return <span className="text-muted-foreground">–</span>;
  const { Icon, className } = RUN_RESULTS[lastRun.result];
  const result = lastRun.result === "nowork" ? "no work" : lastRun.result;
  return (
    <span
      className="inline-flex items-center gap-1 whitespace-nowrap"
      title={`${lastRun.schedule} · ${new Date(lastRun.at * 1_000).toLocaleString()}`}
    >
      <span className="text-muted-foreground">
        {relative(lastRun.at, nowMs)}
      </span>
      <span className={cn("inline-flex items-center gap-0.5", className)}>
        <Icon aria-hidden className="h-3.5 w-3.5" />
        {result}
      </span>
    </span>
  );
}

type AgentIdentity = { label: string; avatarUrl: string | null };

function useAgentIdentities(
  agents: readonly OlympusAgentUsage[],
  groups: readonly OlympusWorkspaceGroup[],
) {
  const records = React.useMemo(() => {
    const byKey = new Map<
      string,
      { publicKey: string | null; label: string; picture: string | null }
    >();
    for (const group of groups) {
      for (const agent of group.agents) {
        byKey.set(`${agent.workspace}/${agent.name}`, {
          publicKey: agent.publicKey,
          label: agent.spec.profile?.displayName?.trim() || agent.name,
          picture: agent.spec.profile?.picture ?? null,
        });
      }
    }
    return byKey;
  }, [groups]);
  const pubkeys = React.useMemo(
    () =>
      agents.flatMap((usage) => {
        const key = records.get(`${usage.workspace}/${usage.name}`)?.publicKey;
        return key ? [key] : [];
      }),
    [agents, records],
  );
  const profiles = useUsersBatchQuery(pubkeys, {
    enabled: pubkeys.length > 0,
  }).data?.profiles;
  return React.useCallback(
    (usage: OlympusAgentUsage): AgentIdentity => {
      const record = records.get(`${usage.workspace}/${usage.name}`);
      const profile = record?.publicKey
        ? profiles?.[record.publicKey]
        : undefined;
      return {
        label: profile?.displayName?.trim() || record?.label || usage.name,
        avatarUrl: profile?.avatarUrl ?? record?.picture ?? null,
      };
    },
    [profiles, records],
  );
}

function WindowToggle({
  onChange,
  testId,
  value,
}: {
  onChange: (value: OlympusUsageWindowKey) => void;
  testId: string;
  value: OlympusUsageWindowKey;
}) {
  return (
    <SegmentedControl
      legend="Usage window"
      onValueChange={onChange}
      optionTestIdPrefix={`${testId}-option`}
      options={WINDOW_OPTIONS}
      size="compact"
      testId={testId}
      value={value}
    />
  );
}

function quotaTone(ratio: number) {
  if (ratio >= 0.9) return { bar: "bg-destructive", text: "text-destructive" };
  if (ratio >= 0.7) {
    return {
      bar: "bg-amber-500",
      text: "text-amber-700 dark:text-amber-300",
    };
  }
  return { bar: "bg-primary", text: "text-foreground" };
}

function AccountQuota({
  accounts,
  nowMs,
}: {
  accounts: OlympusAccountUsage | null;
  nowMs: number;
}) {
  return (
    <section
      aria-labelledby="olympus-usage-accounts"
      className="space-y-3"
      data-testid="olympus-usage-accounts"
    >
      <div className="flex items-baseline justify-between gap-2">
        <h3
          className="flex items-center gap-1.5 text-sm font-semibold text-foreground"
          id="olympus-usage-accounts"
        >
          <Gauge aria-hidden className="h-4 w-4 text-muted-foreground" />
          Hecate account quota
        </h3>
        {accounts ? (
          <span className="text-xs text-muted-foreground">
            Updated {relative(accounts.at, nowMs)}
          </span>
        ) : null}
      </div>
      {!accounts || accounts.accounts.length === 0 ? (
        <p className="text-xs text-muted-foreground">
          No account quota from Hecate yet.
        </p>
      ) : (
        <ul className="grid gap-2 sm:grid-cols-2">
          {accounts.accounts.map((account) => {
            const tone = quotaTone(account.usedRatio);
            const percent = Math.round(account.usedRatio * 100);
            return (
              <li
                className="space-y-1.5 rounded-xl border border-border/60 bg-card px-3 py-2"
                key={`${account.provider}/${account.credential}/${account.window}`}
              >
                <div className="flex items-baseline justify-between gap-2 text-xs">
                  <span className="min-w-0 truncate">
                    <span className="font-medium text-foreground">
                      {account.provider}
                    </span>{" "}
                    <span className="text-muted-foreground">
                      {account.credential} · {account.window}
                    </span>
                  </span>
                  <span
                    className={cn(
                      "inline-flex shrink-0 items-center gap-1 font-medium tabular-nums",
                      tone.text,
                    )}
                  >
                    {account.usedRatio >= 0.9 ? (
                      <CircleAlert aria-hidden className="h-3.5 w-3.5" />
                    ) : null}
                    {percent}% used
                  </span>
                </div>
                <div
                  aria-label={`${account.provider} ${account.credential} ${account.window}`}
                  aria-valuemax={100}
                  aria-valuemin={0}
                  aria-valuenow={percent}
                  className="h-1.5 overflow-hidden rounded-full bg-muted/70"
                  role="progressbar"
                >
                  <div
                    className={cn("h-full rounded-full", tone.bar)}
                    style={{
                      width: `${Math.max(account.usedRatio > 0 ? 2 : 0, percent)}%`,
                    }}
                  />
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}

function EmptyUsage({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="rounded-2xl border border-dashed border-border/70 px-6 py-10 text-center"
      data-testid="olympus-usage-empty"
    >
      <p className="text-sm font-medium text-foreground">No usage yet</p>
      <p className="mt-1 text-xs text-muted-foreground">{children}</p>
    </div>
  );
}

const HEAD_CELL =
  "px-3 py-2 text-left text-2xs font-semibold uppercase tracking-[0.12em] text-muted-foreground";
const NUMBER_CELL = "px-3 py-2.5 text-right tabular-nums";

export function OlympusUsageTable({
  accounts,
  agents,
  groups,
  nowMs,
  windowKey,
  onWindowChange,
}: {
  accounts: OlympusAccountUsage | null;
  agents: readonly OlympusAgentUsage[];
  groups: readonly OlympusWorkspaceGroup[];
  nowMs: number;
  windowKey: OlympusUsageWindowKey;
  onWindowChange: (value: OlympusUsageWindowKey) => void;
}) {
  const palette = useModelPalette(agents);
  const identity = useAgentIdentities(agents, groups);
  const summary = React.useMemo(
    () => summarizeOlympusUsage(agents, windowKey),
    [agents, windowKey],
  );
  const scale = summary.rows.reduce((max, row) => Math.max(max, row.tokens), 0);
  const updatedAt = agents.reduce((max, agent) => Math.max(max, agent.at), 0);

  return (
    <div className="space-y-6" data-testid="olympus-usage-panel">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="space-y-0.5">
          <h3 className="text-sm font-semibold text-foreground">
            Tokens by agent
          </h3>
          <p className="text-xs text-muted-foreground">
            {formatCompactCount(summary.total.tokens)} tokens in the last{" "}
            {windowKey === "24h" ? "24 hours" : "7 days"}
            {updatedAt ? ` · updated ${relative(updatedAt, nowMs)}` : ""}
          </p>
        </div>
        <WindowToggle
          onChange={onWindowChange}
          testId="olympus-usage-window"
          value={windowKey}
        />
      </div>

      <ModelLegend agents={agents} palette={palette} />

      <div className="overflow-x-auto rounded-2xl border border-border/70 bg-card">
        <table
          className="w-full min-w-[720px] text-sm"
          data-testid="olympus-usage-table"
        >
          <thead className="border-b border-border/70">
            <tr>
              <th className={HEAD_CELL} scope="col">
                Agent
              </th>
              <th className={cn(HEAD_CELL, "w-[28%]")} scope="col">
                Tokens
              </th>
              <th className={cn(HEAD_CELL, "text-right")} scope="col">
                Turns
              </th>
              <th className={cn(HEAD_CELL, "text-right")} scope="col">
                Runs
              </th>
              <th className={cn(HEAD_CELL, "text-right")} scope="col">
                Failed
              </th>
              <th className={HEAD_CELL} scope="col">
                Last run
              </th>
              <th className={cn(HEAD_CELL, "text-right")} scope="col">
                Share
              </th>
            </tr>
          </thead>
          <tbody>
            {summary.rows.map((row) => {
              const who = identity(row.usage);
              return (
                <tr
                  className="border-b border-border/50 last:border-b-0"
                  data-testid={`olympus-usage-row-${row.usage.workspace}-${row.usage.name}`}
                  key={`${row.usage.author}:${row.usage.d}`}
                >
                  <th className="px-3 py-2.5 text-left font-normal" scope="row">
                    <span className="flex items-center gap-2.5">
                      <ProfileAvatar
                        avatarUrl={who.avatarUrl}
                        className="h-7 w-7 shrink-0 text-2xs"
                        label={who.label}
                        shape="squircle"
                      />
                      <span className="min-w-0">
                        <span className="block truncate font-medium text-foreground">
                          {who.label}
                        </span>
                        <span className="block truncate text-xs text-muted-foreground">
                          {row.usage.workspace}
                          {row.usage.harness ? ` · ${row.usage.harness}` : ""}
                        </span>
                      </span>
                    </span>
                  </th>
                  <td className="px-3 py-2.5">
                    <div className="flex items-center gap-3">
                      <span
                        className="w-12 shrink-0 text-right font-medium tabular-nums text-foreground"
                        title={`${formatExact(row.tokens)} tokens`}
                      >
                        {formatCompactCount(row.tokens)}
                      </span>
                      <ModelBar
                        className="min-w-16 flex-1"
                        models={row.models}
                        palette={palette}
                        scale={scale}
                      />
                    </div>
                  </td>
                  <td className={NUMBER_CELL}>
                    {formatCompactCount(row.window?.turns ?? 0)}
                  </td>
                  <td className={NUMBER_CELL}>
                    {formatCompactCount(row.window?.runs ?? 0)}
                  </td>
                  <td className={NUMBER_CELL}>
                    <FailedRuns count={row.window?.failedRuns ?? 0} />
                  </td>
                  <td className="px-3 py-2.5 text-xs">
                    <LastRun lastRun={row.usage.lastRun} nowMs={nowMs} />
                  </td>
                  <td className={cn(NUMBER_CELL, "text-muted-foreground")}>
                    {formatShare(row.window?.share ?? null)}
                  </td>
                </tr>
              );
            })}
          </tbody>
          <tfoot className="border-t border-border/70 bg-muted/30">
            <tr data-testid="olympus-usage-total">
              <th
                className="px-3 py-2.5 text-left font-semibold text-foreground"
                scope="row"
              >
                Total
              </th>
              <td className="px-3 py-2.5">
                <div className="flex items-center gap-3">
                  <span
                    className="w-12 shrink-0 text-right font-semibold tabular-nums text-foreground"
                    title={`${formatExact(summary.total.tokens)} tokens`}
                  >
                    {formatCompactCount(summary.total.tokens)}
                  </span>
                  <ModelBar
                    className="min-w-16 flex-1"
                    models={summary.total.models}
                    palette={palette}
                    scale={summary.total.tokens}
                  />
                </div>
              </td>
              <td className={cn(NUMBER_CELL, "font-semibold")}>
                {formatCompactCount(summary.total.turns)}
              </td>
              <td className={cn(NUMBER_CELL, "font-semibold")}>
                {formatCompactCount(summary.total.runs)}
              </td>
              <td className={cn(NUMBER_CELL, "font-semibold")}>
                <FailedRuns count={summary.total.failedRuns} />
              </td>
              <td className="px-3 py-2.5" />
              <td className={cn(NUMBER_CELL, "text-muted-foreground")}>
                {summary.total.tokens > 0 ? "100%" : "–"}
              </td>
            </tr>
          </tfoot>
        </table>
      </div>

      <AccountQuota accounts={accounts} nowMs={nowMs} />
    </div>
  );
}

function Stat({
  label,
  children,
  title,
}: {
  label: string;
  children: React.ReactNode;
  title?: string;
}) {
  return (
    <div className="min-w-0 space-y-0.5">
      <dt className="text-2xs font-semibold uppercase tracking-[0.12em] text-muted-foreground">
        {label}
      </dt>
      <dd
        className="truncate text-sm font-medium tabular-nums text-foreground"
        title={title}
      >
        {children}
      </dd>
    </div>
  );
}

export function OlympusAgentUsageBlock({
  agents,
  nowMs,
  usage,
  windowKey,
  onWindowChange,
}: {
  agents: readonly OlympusAgentUsage[];
  nowMs: number;
  usage: OlympusAgentUsage;
  windowKey: OlympusUsageWindowKey;
  onWindowChange: (value: OlympusUsageWindowKey) => void;
}) {
  const palette = useModelPalette(agents);
  const stats = usage.windows[windowKey];
  const models = windowModelTokens(stats);
  const tokens = models.reduce((sum, entry) => sum + entry.tokens, 0);
  const parts = foldModels(models, palette);
  return (
    <section
      aria-label="Token usage"
      className="space-y-3 rounded-2xl border border-border/70 bg-card px-4 py-3"
      data-testid="olympus-agent-usage"
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h3 className="text-sm font-semibold text-foreground">Usage</h3>
        <WindowToggle
          onChange={onWindowChange}
          testId="olympus-agent-usage-window"
          value={windowKey}
        />
      </div>
      <dl className="grid grid-cols-3 gap-x-4 gap-y-3 sm:grid-cols-6">
        <Stat label="Tokens" title={`${formatExact(tokens)} tokens`}>
          {formatCompactCount(tokens)}
        </Stat>
        <Stat label="Turns">{formatCompactCount(stats?.turns ?? 0)}</Stat>
        <Stat label="Runs">{formatCompactCount(stats?.runs ?? 0)}</Stat>
        <Stat label="Failed">
          <FailedRuns count={stats?.failedRuns ?? 0} />
        </Stat>
        <Stat label="Share">{formatShare(stats?.share ?? null)}</Stat>
        <Stat label="API errors">
          {stats?.apiErrors ? (
            <span className="inline-flex items-center gap-1 text-destructive">
              <CircleAlert aria-hidden className="h-3.5 w-3.5" />
              {stats.apiErrors}
            </span>
          ) : (
            <span className="text-muted-foreground">0</span>
          )}
        </Stat>
      </dl>
      <ModelBar
        className="h-2"
        models={models}
        palette={palette}
        scale={tokens}
      />
      {parts.length > 0 ? (
        <ul className="space-y-1 text-xs">
          {parts.map((part) => (
            <li className="flex items-center gap-2" key={part.label}>
              <span
                aria-hidden
                className={cn("h-2 w-2 rounded-full", part.swatch)}
              />
              <span className="min-w-0 flex-1 truncate text-muted-foreground">
                {part.label}
              </span>
              <span
                className="tabular-nums text-foreground"
                title={formatExact(part.tokens)}
              >
                {formatCompactCount(part.tokens)}
              </span>
            </li>
          ))}
        </ul>
      ) : null}
      <p className="flex flex-wrap items-center gap-x-2 text-xs text-muted-foreground">
        Last run{usage.lastRun ? ` (${usage.lastRun.schedule})` : ""}:{" "}
        <LastRun lastRun={usage.lastRun} nowMs={nowMs} />
        <span className="ml-auto">Updated {relative(usage.at, nowMs)}</span>
      </p>
    </section>
  );
}

export function OlympusUsagePanel({
  workspace,
  agent,
}: {
  workspace?: string;
  agent?: string;
}) {
  const usage = useOlympusUsage();
  const nowMs = useNow(60_000);
  const [windowKey, setWindowKey] = React.useState<OlympusUsageWindowKey>(
    OLYMPUS_USAGE_WINDOWS[0],
  );
  const single = workspace !== undefined && agent !== undefined;

  if (usage.isLoading && usage.agents.length === 0) {
    return (
      <div className="flex items-center gap-2 py-6 text-sm text-muted-foreground">
        <Spinner aria-hidden className="h-4 w-4" />
        Loading usage…
      </div>
    );
  }
  if (usage.error && usage.agents.length === 0) {
    return (
      <p className="rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive">
        Couldn’t load usage: {usage.error.message}
      </p>
    );
  }

  if (single) {
    const record = usage.agents.find(
      (candidate) =>
        candidate.workspace === workspace && candidate.name === agent,
    );
    return record ? (
      <OlympusAgentUsageBlock
        agents={usage.agents}
        nowMs={nowMs}
        onWindowChange={setWindowKey}
        usage={record}
        windowKey={windowKey}
      />
    ) : (
      <EmptyUsage>{EMPTY_REASON}</EmptyUsage>
    );
  }

  if (usage.agents.length === 0) {
    return (
      <div className="space-y-6">
        <EmptyUsage>{EMPTY_REASON}</EmptyUsage>
        {usage.accounts ? (
          <AccountQuota accounts={usage.accounts} nowMs={nowMs} />
        ) : null}
      </div>
    );
  }

  return (
    <OlympusUsageTable
      accounts={usage.accounts}
      agents={usage.agents}
      groups={usage.groups}
      nowMs={nowMs}
      onWindowChange={setWindowKey}
      windowKey={windowKey}
    />
  );
}
