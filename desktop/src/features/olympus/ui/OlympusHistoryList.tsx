import { Check, X } from "lucide-react";

import type { OlympusCondition } from "@/features/agents/lib/olympusAgents";
import type { OlympusHistoryEntry } from "../lib/olympusHistory";
import {
  formatOlympusAgo,
  formatOlympusDate,
  OlympusNone,
} from "./OlympusParts";

const ACTIONS: Record<string, string> = {
  suspend: "Suspend",
  resume: "Resume",
  update: "Edit",
  patch: "Change",
  "add-mcp": "Add MCP server",
  "remove-mcp": "Remove MCP server",
  "set-memory": "Memory change",
  create: "Create",
  delete: "Delete",
  approve: "Approve proposal",
  reject: "Reject proposal",
  "suspend-schedule": "Suspend schedule",
  "resume-schedule": "Resume schedule",
  "run-now": "Run now",
};

function target(entry: OlympusHistoryEntry) {
  if (entry.proposal) return entry.proposal;
  if (entry.schedule) return `schedule ${entry.schedule}`;
  if (entry.agent) return entry.agent;
  return entry.workspace ? `workspace ${entry.workspace}` : "";
}

export function OlympusHistoryList({
  entries,
  testId,
}: {
  entries: readonly OlympusHistoryEntry[];
  testId?: string;
}) {
  if (entries.length === 0) {
    return <OlympusNone>No changes from this app yet.</OlympusNone>;
  }
  return (
    <ol className="space-y-1.5" data-testid={testId}>
      {entries.map((entry) => {
        const accepted = entry.status === "accepted";
        const Icon = accepted ? Check : X;
        return (
          <li
            className="grid grid-cols-[auto_minmax(0,1fr)_auto] items-start gap-2 text-sm"
            data-status={entry.status}
            key={entry.id}
          >
            <Icon
              aria-hidden
              className={
                accepted
                  ? "mt-0.5 h-4 w-4 text-emerald-700 dark:text-emerald-300"
                  : "mt-0.5 h-4 w-4 text-destructive"
              }
            />
            <span className="min-w-0">
              <span className="text-foreground">
                {ACTIONS[entry.action] ?? entry.action}
              </span>
              <span className="text-muted-foreground"> {target(entry)}</span>
              <span className="block break-words text-xs text-muted-foreground">
                {accepted ? "Accepted" : "Refused"}
                {entry.reason ? `: ${entry.reason}` : ""}
              </span>
            </span>
            <time
              className="text-xs text-muted-foreground"
              dateTime={new Date(entry.createdAt * 1_000).toISOString()}
              title={formatOlympusDate(entry.createdAt) ?? undefined}
            >
              {formatOlympusAgo(entry.createdAt)}
            </time>
          </li>
        );
      })}
    </ol>
  );
}

export function OlympusConditions({
  conditions,
}: {
  conditions: readonly OlympusCondition[];
}) {
  if (conditions.length === 0) return null;
  return (
    <div className="space-y-2">
      <h3 className="text-xs font-semibold text-muted-foreground">
        Conditions
      </h3>
      <ul className="grid gap-1.5 sm:grid-cols-2">
        {conditions.map((condition) => {
          const ok = condition.status === "True";
          const Icon = ok ? Check : X;
          return (
            <li
              aria-label={`${condition.type} ${condition.status}${condition.reason ? ` ${condition.reason}` : ""}`}
              className="flex items-start gap-2 rounded-lg border border-border/50 px-2.5 py-1.5 text-xs"
              key={condition.type}
            >
              <Icon
                aria-hidden
                className={
                  ok
                    ? "mt-0.5 h-3.5 w-3.5 shrink-0 text-emerald-700 dark:text-emerald-300"
                    : "mt-0.5 h-3.5 w-3.5 shrink-0 text-amber-700 dark:text-amber-300"
                }
              />
              <span className="min-w-0">
                <span className="font-medium text-foreground">
                  {condition.type}
                </span>
                <span className="text-muted-foreground">
                  {" "}
                  {condition.status}
                  {condition.reason ? ` · ${condition.reason}` : ""}
                </span>
                {condition.message ? (
                  <span className="block break-words text-muted-foreground">
                    {condition.message}
                  </span>
                ) : null}
                {condition.lastTransitionTime ? (
                  <span className="block text-muted-foreground">
                    {formatOlympusAgo(condition.lastTransitionTime)}
                  </span>
                ) : null}
              </span>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
