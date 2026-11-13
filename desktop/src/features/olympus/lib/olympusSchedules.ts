import type {
  OlympusAgent,
  OlympusSchedule,
  OlympusWorkspaceGroup,
} from "@/features/agents/lib/olympusAgents";
import { nextOlympusRun } from "./olympusCron";

export type OlympusScheduleRow = {
  key: string;
  operator: string;
  workspace: string;
  agent: OlympusAgent;
  schedule: OlympusSchedule;
  suspended: boolean;
  failed: boolean;
  nextRun: Date | null;
};

export function olympusScheduleMode(schedule: OlympusSchedule): string {
  if (schedule.asAgent) return "Script as the agent";
  if (schedule.prompt && schedule.script) return "Script, then prompt";
  if (schedule.script) return "Script";
  return "Prompt";
}

export function listOlympusSchedules(
  groups: readonly OlympusWorkspaceGroup[],
  now: number,
): OlympusScheduleRow[] {
  const rows: OlympusScheduleRow[] = [];
  for (const group of groups) {
    const workspaceSuspended = group.workspace?.suspend === true;
    for (const agent of group.agents) {
      for (const schedule of agent.schedules) {
        const suspended =
          schedule.suspend || agent.spec.suspend || workspaceSuspended;
        rows.push({
          key: `${group.key}:${agent.name}:${schedule.name}`,
          operator: agent.author,
          workspace: group.name,
          agent,
          schedule,
          suspended,
          failed: schedule.lastResult === "Failed",
          nextRun: suspended
            ? null
            : nextOlympusRun(schedule.cron, schedule.timeZone, now),
        });
      }
    }
  }
  return rows;
}

export function olympusScheduleSupportsActions(schedule: OlympusSchedule) {
  return schedule.gitopsFields !== null;
}
