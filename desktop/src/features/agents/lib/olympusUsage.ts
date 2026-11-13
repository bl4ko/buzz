import type { RelayEvent } from "@/shared/api/types";
import { KIND_OLYMPUS_USAGE } from "@/shared/constants/kinds";

export const OLYMPUS_USAGE_WINDOWS = ["24h", "7d"] as const;
export type OlympusUsageWindowKey = (typeof OLYMPUS_USAGE_WINDOWS)[number];

export const OLYMPUS_USAGE_ACCOUNTS_D = "hecate";

const SUBSET_TOKEN_TYPES = new Set(["cached_input", "reasoning_output"]);
const RUN_RESULTS = ["succeeded", "failed", "nowork"] as const;

export type OlympusUsageWindow = {
  tokens: Record<string, Record<string, number>>;
  turns: number;
  apiErrors: number;
  runs: number;
  failedRuns: number;
  share: number | null;
};

export type OlympusUsageLastRun = {
  schedule: string;
  at: number;
  result: (typeof RUN_RESULTS)[number];
};

export type OlympusAgentUsage = {
  author: string;
  d: string;
  workspace: string;
  namespace: string;
  name: string;
  harness: string | null;
  at: number;
  windows: Record<OlympusUsageWindowKey, OlympusUsageWindow | null>;
  lastRun: OlympusUsageLastRun | null;
};

export type OlympusAccountQuota = {
  provider: string;
  credential: string;
  window: string;
  usedRatio: number;
};

export type OlympusAccountUsage = {
  author: string;
  at: number;
  accounts: OlympusAccountQuota[];
};

export type OlympusUsageState = {
  agents: OlympusAgentUsage[];
  accounts: OlympusAccountUsage | null;
};

export type OlympusModelTokens = { model: string; tokens: number };

export type OlympusUsageRow = {
  usage: OlympusAgentUsage;
  window: OlympusUsageWindow | null;
  tokens: number;
  models: OlympusModelTokens[];
};

export type OlympusUsageSummary = {
  rows: OlympusUsageRow[];
  total: {
    tokens: number;
    turns: number;
    runs: number;
    failedRuns: number;
    apiErrors: number;
    models: OlympusModelTokens[];
  };
};

type Json = Record<string, unknown>;

function isObject(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function text(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function count(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? value
    : 0;
}

function singleTag(event: RelayEvent, name: string): string | null {
  const values = event.tags.filter((tag) => tag[0] === name);
  return values.length === 1 && typeof values[0][1] === "string"
    ? values[0][1]
    : null;
}

function isNewer(candidate: RelayEvent, current: RelayEvent) {
  return (
    candidate.created_at > current.created_at ||
    (candidate.created_at === current.created_at && candidate.id < current.id)
  );
}

export function mergeOlympusUsageEvents(
  current: readonly RelayEvent[],
  incoming: readonly RelayEvent[],
): RelayEvent[] {
  const newest = new Map<string, RelayEvent>();
  for (const event of [...current, ...incoming]) {
    const d = singleTag(event, "d");
    if (event.kind !== KIND_OLYMPUS_USAGE || !d) continue;
    const key = `${event.pubkey}:${d}`;
    const existing = newest.get(key);
    if (!existing || isNewer(event, existing)) newest.set(key, event);
  }
  return [...newest.values()];
}

function parseTokens(value: unknown): Record<string, Record<string, number>> {
  if (!isObject(value)) return {};
  const tokens: Record<string, Record<string, number>> = {};
  for (const [model, types] of Object.entries(value)) {
    if (!model || !isObject(types)) continue;
    const parsed: Record<string, number> = {};
    for (const [type, amount] of Object.entries(types)) {
      const n = count(amount);
      if (type && n > 0) parsed[type] = n;
    }
    if (Object.keys(parsed).length > 0) tokens[model] = parsed;
  }
  return tokens;
}

function parseWindow(value: unknown): OlympusUsageWindow | null {
  if (!isObject(value)) return null;
  const share =
    typeof value.share === "number" &&
    Number.isFinite(value.share) &&
    value.share >= 0 &&
    value.share <= 1
      ? value.share
      : null;
  return {
    tokens: parseTokens(value.tokens),
    turns: count(value.turns),
    apiErrors: count(value.apiErrors),
    runs: count(value.runs),
    failedRuns: count(value.failedRuns),
    share,
  };
}

function parseLastRun(value: unknown): OlympusUsageLastRun | null {
  if (!isObject(value)) return null;
  const schedule = text(value.schedule);
  const result = RUN_RESULTS.find((candidate) => candidate === value.result);
  if (!schedule || !result || count(value.at) === 0) return null;
  return { schedule, at: value.at as number, result };
}

function parseContent(event: RelayEvent): Json | null {
  try {
    const content: unknown = JSON.parse(event.content);
    return isObject(content) && content.v === 1 ? content : null;
  } catch {
    return null;
  }
}

function parseAccounts(value: unknown): OlympusAccountQuota[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((entry) => {
    if (!isObject(entry)) return [];
    const provider = text(entry.provider);
    const credential = text(entry.credential);
    const window = text(entry.window);
    const usedRatio = entry.usedRatio;
    return provider &&
      credential &&
      window &&
      typeof usedRatio === "number" &&
      Number.isFinite(usedRatio)
      ? [
          {
            provider,
            credential,
            window,
            usedRatio: Math.min(1, Math.max(0, usedRatio)),
          },
        ]
      : [];
  });
}

export function parseOlympusUsage(
  event: RelayEvent,
  trustedAuthors: ReadonlySet<string>,
):
  | { type: "agent"; usage: OlympusAgentUsage }
  | { type: "accounts"; accounts: OlympusAccountUsage }
  | null {
  if (
    event.kind !== KIND_OLYMPUS_USAGE ||
    !trustedAuthors.has(event.pubkey) ||
    singleTag(event, "status") !== "active"
  ) {
    return null;
  }
  const d = singleTag(event, "d");
  const content = parseContent(event);
  if (!d || !content) return null;
  const at = count(content.at) || event.created_at;
  if (d === OLYMPUS_USAGE_ACCOUNTS_D) {
    return {
      type: "accounts",
      accounts: {
        author: event.pubkey,
        at,
        accounts: parseAccounts(content.accounts).sort(
          (left, right) =>
            left.provider.localeCompare(right.provider) ||
            left.credential.localeCompare(right.credential) ||
            left.window.localeCompare(right.window),
        ),
      },
    };
  }
  const workspace = text(content.workspace);
  const namespace = text(content.namespace);
  const name = text(content.name);
  const workspaceTag = singleTag(event, "workspace");
  if (
    !workspace ||
    !namespace ||
    !name ||
    d !== `${namespace}/${name}` ||
    (workspaceTag !== null && workspaceTag !== workspace)
  ) {
    return null;
  }
  const windows = isObject(content.windows) ? content.windows : {};
  return {
    type: "agent",
    usage: {
      author: event.pubkey,
      d,
      workspace,
      namespace,
      name,
      harness: text(content.harness),
      at,
      windows: {
        "24h": parseWindow(windows["24h"]),
        "7d": parseWindow(windows["7d"]),
      },
      lastRun: parseLastRun(content.lastRun),
    },
  };
}

export function buildOlympusUsage(
  events: readonly RelayEvent[],
  trustedAuthors: ReadonlySet<string>,
): OlympusUsageState {
  const agents: OlympusAgentUsage[] = [];
  let accounts: OlympusAccountUsage | null = null;
  for (const event of mergeOlympusUsageEvents([], events)) {
    const parsed = parseOlympusUsage(event, trustedAuthors);
    if (parsed?.type === "agent") agents.push(parsed.usage);
    else if (
      parsed?.type === "accounts" &&
      (!accounts || parsed.accounts.at > accounts.at)
    ) {
      accounts = parsed.accounts;
    }
  }
  agents.sort(
    (left, right) =>
      left.workspace.localeCompare(right.workspace) ||
      left.name.localeCompare(right.name),
  );
  return { agents, accounts };
}

export function modelTokenTotal(types: Readonly<Record<string, number>>) {
  if (typeof types.total === "number") return types.total;
  let sum = 0;
  for (const [type, amount] of Object.entries(types)) {
    if (!SUBSET_TOKEN_TYPES.has(type)) sum += amount;
  }
  return sum;
}

export function windowModelTokens(
  window: OlympusUsageWindow | null,
): OlympusModelTokens[] {
  if (!window) return [];
  return Object.entries(window.tokens)
    .map(([model, types]) => ({ model, tokens: modelTokenTotal(types) }))
    .filter((entry) => entry.tokens > 0)
    .sort(
      (left, right) =>
        right.tokens - left.tokens || left.model.localeCompare(right.model),
    );
}

function addModels(
  totals: Map<string, number>,
  models: readonly OlympusModelTokens[],
) {
  for (const entry of models) {
    totals.set(entry.model, (totals.get(entry.model) ?? 0) + entry.tokens);
  }
}

export function summarizeOlympusUsage(
  agents: readonly OlympusAgentUsage[],
  windowKey: OlympusUsageWindowKey,
): OlympusUsageSummary {
  const modelTotals = new Map<string, number>();
  const total = { tokens: 0, turns: 0, runs: 0, failedRuns: 0, apiErrors: 0 };
  const rows = agents.map((usage) => {
    const window = usage.windows[windowKey];
    const models = windowModelTokens(window);
    const tokens = models.reduce((sum, entry) => sum + entry.tokens, 0);
    addModels(modelTotals, models);
    total.tokens += tokens;
    total.turns += window?.turns ?? 0;
    total.runs += window?.runs ?? 0;
    total.failedRuns += window?.failedRuns ?? 0;
    total.apiErrors += window?.apiErrors ?? 0;
    return { usage, window, tokens, models };
  });
  rows.sort(
    (left, right) =>
      right.tokens - left.tokens ||
      left.usage.workspace.localeCompare(right.usage.workspace) ||
      left.usage.name.localeCompare(right.usage.name),
  );
  return {
    rows,
    total: {
      ...total,
      models: [...modelTotals.entries()]
        .map(([model, tokens]) => ({ model, tokens }))
        .sort(
          (left, right) =>
            right.tokens - left.tokens || left.model.localeCompare(right.model),
        ),
    },
  };
}

export function olympusUsageModelOrder(
  agents: readonly OlympusAgentUsage[],
): string[] {
  const totals = new Map<string, number>();
  for (const agent of agents) {
    for (const key of OLYMPUS_USAGE_WINDOWS) {
      addModels(totals, windowModelTokens(agent.windows[key]));
    }
  }
  return [...totals.entries()]
    .sort(
      (left, right) => right[1] - left[1] || left[0].localeCompare(right[0]),
    )
    .map(([model]) => model);
}

const COMPACT_UNITS = [
  { value: 1e12, suffix: "T" },
  { value: 1e9, suffix: "B" },
  { value: 1e6, suffix: "M" },
  { value: 1e3, suffix: "k" },
] as const;

export function formatCompactCount(value: number): string {
  const n = Math.max(0, Math.round(value));
  for (const unit of COMPACT_UNITS) {
    if (n >= unit.value * 0.9995) {
      const scaled = n / unit.value;
      const digits = scaled < 10 ? 1 : 0;
      return `${Number(scaled.toFixed(digits))}${unit.suffix}`;
    }
  }
  return String(n);
}

export function formatShare(share: number | null): string {
  if (share === null) return "–";
  if (share > 0 && share < 0.01) return "<1%";
  return `${Math.round(share * 100)}%`;
}
