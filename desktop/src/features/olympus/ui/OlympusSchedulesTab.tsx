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
  formatOlympusAgo,
  formatOlympusDate,
  formatOlympusIn,
  OlympusChip,
  OlympusEmptyState,
  OlympusGitLock,
  OlympusRunResult,
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
  const [failedOnly, setFailedOnly] = React.useState(false);
  const failedId = React.useId();
  const rows = React.useMemo(
    () =>
      listOlympusSchedules(olympus.groups, now).filter(
        (row) => agent === undefined || row.agent.d === agent,
      ),
    [agent, now, olympus.groups],
  );
  const failed = rows.filter((row) => row.failed).length;
  const shown = failedOnly ? rows.filter((row) => row.failed) : rows;

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
        <div className="flex flex-wrap items-center justify-between gap-3">
          <p className="text-xs text-muted-foreground">
            {rows.length} {rows.length === 1 ? "schedule" : "schedules"}
            {failed > 0 ? `, ${failed} with a failed last run` : ""}
          </p>
          <label
            className="flex items-center gap-2 text-xs text-muted-foreground"
            htmlFor={failedId}
          >
            <Switch
              checked={failedOnly}
              id={failedId}
              onCheckedChange={setFailedOnly}
            />
            Only failed
          </label>
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
