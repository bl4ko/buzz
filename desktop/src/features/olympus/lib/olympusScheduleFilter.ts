import { olympusAgentLabel } from "@/features/agents/lib/olympusAgents";
import type { OlympusScheduleRow } from "./olympusSchedules";

export type OlympusScheduleFilter = {
  workspace: string | null;
  agent: string | null;
  failedOnly: boolean;
};

export const OLYMPUS_SCHEDULE_FILTER_KEY = "buzz.olympus.schedule-filter.v1";

const EMPTY: OlympusScheduleFilter = {
  workspace: null,
  agent: null,
  failedOnly: false,
};

function name(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

export function parseOlympusScheduleFilter(
  raw: string | null,
): OlympusScheduleFilter {
  if (!raw) return EMPTY;
  try {
    const value = JSON.parse(raw) as Record<string, unknown>;
    return {
      workspace: name(value.workspace),
      agent: name(value.agent),
      failedOnly: value.failedOnly === true,
    };
  } catch {
    return EMPTY;
  }
}

export function loadOlympusScheduleFilter(): OlympusScheduleFilter {
  try {
    return parseOlympusScheduleFilter(
      localStorage.getItem(OLYMPUS_SCHEDULE_FILTER_KEY),
    );
  } catch {
    return EMPTY;
  }
}

export function saveOlympusScheduleFilter(filter: OlympusScheduleFilter) {
  try {
    localStorage.setItem(OLYMPUS_SCHEDULE_FILTER_KEY, JSON.stringify(filter));
  } catch {
    return;
  }
}

export function olympusScheduleAgentKey(row: OlympusScheduleRow): string {
  return `${row.workspace}/${row.agent.name}`;
}

export function olympusScheduleFilterOptions(
  rows: readonly OlympusScheduleRow[],
  workspace: string | null,
) {
  const workspaces = [...new Set(rows.map((row) => row.workspace))].sort();
  const agents = new Map<string, string>();
  for (const row of rows) {
    if (workspace !== null && row.workspace !== workspace) continue;
    const label = olympusAgentLabel(row.agent);
    agents.set(
      olympusScheduleAgentKey(row),
      workspace === null && workspaces.length > 1
        ? `${label} · ${row.workspace}`
        : label,
    );
  }
  return {
    workspaces,
    agents: [...agents.entries()]
      .map(([value, label]) => ({ value, label }))
      .sort((a, b) => a.label.localeCompare(b.label)),
  };
}

export function applyOlympusScheduleFilter(
  rows: readonly OlympusScheduleRow[],
  filter: OlympusScheduleFilter,
): OlympusScheduleRow[] {
  return rows.filter(
    (row) =>
      (filter.workspace === null || row.workspace === filter.workspace) &&
      (filter.agent === null ||
        olympusScheduleAgentKey(row) === filter.agent) &&
      (!filter.failedOnly || row.failed),
  );
}

export function activeOlympusScheduleFilter(
  rows: readonly OlympusScheduleRow[],
  filter: OlympusScheduleFilter,
): OlympusScheduleFilter {
  const workspace =
    filter.workspace !== null &&
    rows.some((row) => row.workspace === filter.workspace)
      ? filter.workspace
      : null;
  const agent =
    filter.agent !== null &&
    rows.some(
      (row) =>
        olympusScheduleAgentKey(row) === filter.agent &&
        (workspace === null || row.workspace === workspace),
    )
      ? filter.agent
      : null;
  return { workspace, agent, failedOnly: filter.failedOnly };
}
