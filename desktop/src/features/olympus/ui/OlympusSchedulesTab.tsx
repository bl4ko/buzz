import * as React from "react";
import { CalendarClock, Pause, Play, PlayCircle } from "lucide-react";

import { useAppNavigation } from "@/app/navigation/useAppNavigation";
import { olympusAgentLabel } from "@/features/agents/lib/olympusAgents";
import {
  olympusScheduleRequestKey,
  useOlympusRequestState,
} from "@/features/agents/lib/olympusChangeRequests";
import { OlympusRequestStatus } from "@/features/agents/ui/OlympusAgentParts";
import { useOlympusAgents } from "@/features/agents/useOlympusAgents";
import { Button } from "@/shared/ui/button";
import { Switch } from "@/shared/ui/switch";
import {
  listOlympusSchedules,
  olympusScheduleMode,
  olympusScheduleSupportsActions,
  type OlympusScheduleRow,
} from "../lib/olympusSchedules";
import { olympusFieldLocked } from "../lib/olympusOwnership";
import {
  activeOlympusScheduleFilter,
  applyOlympusScheduleFilter,
  loadOlympusScheduleFilter,
  type OlympusScheduleFilter,
  olympusScheduleFilterOptions,
  saveOlympusScheduleFilter,
} from "../lib/olympusScheduleFilter";
import {
  formatOlympusAgo,
  formatOlympusDate,
  formatOlympusIn,
  OlympusChip,
  OlympusEmptyState,
  OlympusGitLock,
  OlympusRunResult,
  OlympusSelect,
} from "./OlympusParts";

const MINUTE = 60_000;

function useMinuteClock() {
  const [now, setNow] = React.useState(() => Date.now());
  React.useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), MINUTE);
    return () => clearInterval(timer);
  }, []);
  return now;
}

export function OlympusSchedulesTab({ agent }: { agent?: string } = {}) {
  const olympus = useOlympusAgents();
  const now = useMinuteClock();
  const [stored, setStored] = React.useState(loadOlympusScheduleFilter);
  const failedId = React.useId();
  const rows = React.useMemo(
    () =>
      listOlympusSchedules(olympus.groups, now).filter(
        (row) => agent === undefined || row.agent.d === agent,
      ),
    [agent, now, olympus.groups],
  );
  const filter =
    agent === undefined
      ? activeOlympusScheduleFilter(rows, stored)
      : { workspace: null, agent: null, failedOnly: false };
  const options = olympusScheduleFilterOptions(rows, filter.workspace);
  const update = (patch: Partial<OlympusScheduleFilter>) => {
    const next = { ...filter, ...patch };
    setStored(next);
    saveOlympusScheduleFilter(next);
  };
  const shown = applyOlympusScheduleFilter(rows, filter);
  const failed = shown.filter((row) => row.failed).length;
  const filtered = filter.workspace !== null || filter.agent !== null;

  if (rows.length === 0) {
    return (
      <OlympusEmptyState
        icon={CalendarClock}
        testId="olympus-schedules-empty"
        title="No schedules"
      >
        <p>Schedules start agent turns or scripts at fixed times.</p>
      </OlympusEmptyState>
    );
  }

  return (
    <div className="space-y-3" data-testid="olympus-schedules">
      {agent === undefined ? (
        <div
          className="flex flex-wrap items-center justify-between gap-3"
          data-testid="olympus-schedule-filters"
        >
          <p className="text-xs text-muted-foreground">
            {filtered || filter.failedOnly
              ? `${shown.length} of ${rows.length} schedules`
              : `${rows.length} ${rows.length === 1 ? "schedule" : "schedules"}`}
            {failed > 0 ? `, ${failed} with a failed last run` : ""}
          </p>
          <div className="flex flex-wrap items-center gap-2">
            {options.workspaces.length > 1 ? (
              <div className="w-40">
                <OlympusSelect
                  label="Workspace"
                  onChange={(value) =>
                    update({
                      workspace: value || null,
                      agent:
                        value &&
                        filter.agent &&
                        !filter.agent.startsWith(`${value}/`)
                          ? null
                          : filter.agent,
                    })
                  }
                  options={[
                    { value: "", label: "All workspaces" },
                    ...options.workspaces.map((item) => ({
                      value: item,
                      label: item,
                    })),
                  ]}
                  value={filter.workspace ?? ""}
                />
              </div>
            ) : null}
            <div className="w-48">
              <OlympusSelect
                label="Agent"
                onChange={(value) => update({ agent: value || null })}
                options={[
                  { value: "", label: "All agents" },
                  ...options.agents,
                ]}
                value={filter.agent ?? ""}
              />
            </div>
            <label
              className="flex items-center gap-2 pl-1 text-xs text-muted-foreground"
              htmlFor={failedId}
            >
              <Switch
                checked={filter.failedOnly}
                id={failedId}
                onCheckedChange={(failedOnly) => update({ failedOnly })}
              />
              Only failed
            </label>
          </div>
        </div>
      ) : null}
      <div className="overflow-x-auto rounded-xl border border-border/70 bg-card/60">
        <table className="w-full min-w-[46rem] text-left text-sm">
          <thead className="border-b border-border/60 text-xs text-muted-foreground">
            <tr>
              <th className="px-3 py-2 font-medium" scope="col">
                Schedule
              </th>
              <th className="px-3 py-2 font-medium" scope="col">
                When
              </th>
              <th className="px-3 py-2 font-medium" scope="col">
                Next run
              </th>
              <th className="px-3 py-2 font-medium" scope="col">
                Last run
              </th>
              <th className="px-3 py-2 text-right font-medium" scope="col">
                <span className="sr-only">Actions</span>
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border/40">
            {shown.length === 0 ? (
              <tr>
                <td
                  className="px-3 py-6 text-center text-xs text-muted-foreground"
                  colSpan={5}
                  data-testid="olympus-schedules-none-match"
                >
                  No schedule matches the filter.{" "}
                  <button
                    className="font-medium text-foreground underline-offset-2 hover:underline"
                    onClick={() =>
                      update({
                        workspace: null,
                        agent: null,
                        failedOnly: false,
                      })
                    }
                    type="button"
                  >
                    Show all schedules
                  </button>
                </td>
              </tr>
            ) : null}
            {shown.map((row) => (
              <OlympusScheduleRowView
                key={row.key}
                row={row}
                showAgent={agent === undefined}
              />
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function OlympusScheduleRowView({
  row,
  showAgent,
}: {
  row: OlympusScheduleRow;
  showAgent: boolean;
}) {
  const olympus = useOlympusAgents();
  const { goOlympusAgent } = useAppNavigation();
  const { schedule, agent } = row;
  const key = olympusScheduleRequestKey(row.workspace, schedule.name);
  const request = useOlympusRequestState(key);
  const pending = request?.phase === "pending";
  const actions = olympusScheduleSupportsActions(schedule);
  const suspendLocked = olympusFieldLocked(
    { managedBy: agent.managedBy, gitopsFields: schedule.gitopsFields },
    "spec.suspend",
  );
  const send = (action: "suspend-schedule" | "resume-schedule" | "run-now") => {
    void olympus.submitChange(
      key,
      {
        operator: row.operator,
        workspace: row.workspace,
        agent: null,
        schedule: schedule.name,
      },
      { action },
    );
  };
  return (
    <>
      <tr
        className={row.failed ? "bg-destructive/5" : undefined}
        data-testid={`olympus-schedule-${schedule.name}`}
      >
        <td className="px-3 py-2.5 align-top">
          <span className="block font-medium text-foreground">
            {schedule.name}
          </span>
          {showAgent ? (
            <button
              className="text-xs text-muted-foreground underline-offset-2 hover:text-foreground hover:underline"
              onClick={() => void goOlympusAgent(row.workspace, agent.name)}
              type="button"
            >
              {olympusAgentLabel(agent)} · {row.workspace}
            </button>
          ) : null}
          <span className="block text-xs text-muted-foreground">
            {olympusScheduleMode(schedule)}
            {schedule.workspace ? " · on the agent volume" : ""}
          </span>
        </td>
        <td className="px-3 py-2.5 align-top">
          <span className="block font-mono text-xs text-foreground">
            {schedule.cron ?? "None"}
          </span>
          <span className="block text-xs text-muted-foreground">
            {schedule.timeZone ?? "UTC"}
          </span>
        </td>
        <td className="px-3 py-2.5 align-top text-xs">
          {row.suspended ? (
            <OlympusChip icon={Pause}>
              {schedule.suspend ? "Suspended" : "Agent suspended"}
            </OlympusChip>
          ) : row.nextRun ? (
            <span title={row.nextRun.toISOString()}>
              <span className="block text-foreground">
                {formatOlympusIn(row.nextRun)}
              </span>
              <span className="block text-muted-foreground">
                {formatOlympusDate(row.nextRun)}
              </span>
            </span>
          ) : (
            <span className="text-muted-foreground">Unknown</span>
          )}
        </td>
        <td className="px-3 py-2.5 align-top text-xs">
          <OlympusRunResult result={schedule.lastResult} />
          {schedule.lastRunTime ? (
            <span className="mt-1 block text-muted-foreground">
              {formatOlympusAgo(schedule.lastRunTime)}
            </span>
          ) : null}
        </td>
        <td className="px-3 py-2.5 text-right align-top">
          {actions ? (
            <div className="flex justify-end gap-1">
              {suspendLocked ? (
                <span className="inline-flex h-8 items-center px-2">
                  <OlympusGitLock field="Schedule suspend" />
                </span>
              ) : (
                <Button
                  aria-label={`${schedule.suspend ? "Resume" : "Suspend"} schedule ${schedule.name}`}
                  disabled={pending}
                  onClick={() =>
                    send(
                      schedule.suspend ? "resume-schedule" : "suspend-schedule",
                    )
                  }
                  size="icon"
                  type="button"
                  variant="ghost"
                >
                  {schedule.suspend ? <Play /> : <Pause />}
                </Button>
              )}
              <Button
                aria-label={`Run schedule ${schedule.name} now`}
                disabled={pending || row.suspended}
                onClick={() => send("run-now")}
                size="icon"
                type="button"
                variant="ghost"
              >
                <PlayCircle />
              </Button>
            </div>
          ) : null}
        </td>
      </tr>
      {request ? (
        <tr>
          <td className="px-3 pb-2.5" colSpan={5}>
            <OlympusRequestStatus
              state={request}
              testId={`olympus-schedule-request-${schedule.name}`}
            />
          </td>
        </tr>
      ) : null}
    </>
  );
}
