import type * as React from "react";

import type { OlympusRequestState } from "@/features/agents/lib/olympusChangeRequests";
import { cn } from "@/shared/lib/cn";
import { Badge, type BadgeProps } from "@/shared/ui/badge";
import { Spinner } from "@/shared/ui/spinner";

export const OLYMPUS_SELECT_CLASS =
  "flex h-9 w-full rounded-md border border-input bg-background px-3 py-2 text-sm text-foreground shadow-xs disabled:opacity-50 dark:[color-scheme:dark]";

const PHASE_VARIANTS: Record<string, BadgeProps["variant"]> = {
  Online: "success",
  Ready: "info",
  Enrolled: "secondary",
  Pending: "warning",
  Suspended: "outline",
};

export function OlympusPhaseBadge({
  className,
  phase,
}: {
  className?: string;
  phase: string;
}) {
  return (
    <Badge className={className} variant={PHASE_VARIANTS[phase] ?? "secondary"}>
      {phase}
    </Badge>
  );
}

export function formatOlympusTime(value: string | null): string | null {
  if (!value) return null;
  const millis = Date.parse(value);
  if (Number.isNaN(millis)) return value;
  const seconds = Math.max(0, Math.floor((Date.now() - millis) / 1_000));
  if (seconds < 60) return "just now";
  if (seconds < 3_600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86_400) return `${Math.floor(seconds / 3_600)}h ago`;
  return `${Math.floor(seconds / 86_400)}d ago`;
}

const ACTION_LABELS: Record<string, string> = {
  suspend: "Suspend",
  resume: "Resume",
  update: "Edit",
  "add-mcp": "Add MCP server",
  "remove-mcp": "Remove MCP server",
  "set-memory": "Memory change",
  create: "New agent",
  delete: "Delete",
  approve: "Approve",
  reject: "Reject",
  patch: "Change",
  "suspend-schedule": "Suspend schedule",
  "resume-schedule": "Resume schedule",
  "run-now": "Run now",
};

export function OlympusRequestStatus({
  className,
  state,
  testId,
}: {
  className?: string;
  state: OlympusRequestState | null;
  testId: string;
}) {
  const label = state ? (ACTION_LABELS[state.action] ?? state.action) : "";
  let body: React.ReactNode = null;
  let tone = "border-border/60 bg-muted/30 text-muted-foreground";
  if (state?.phase === "pending") {
    body = (
      <>
        <Spinner aria-hidden className="h-4 w-4" />
        <span>{label}: waiting for Hephaestus…</span>
      </>
    );
  } else if (state?.phase === "accepted") {
    tone =
      "border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300";
    body = (
      <span>
        {label}: accepted{state.reason ? ` (${state.reason})` : ""}. The state
        updates when Hephaestus publishes it.
      </span>
    );
  } else if (state?.phase === "refused") {
    tone = "border-destructive/30 bg-destructive/10 text-destructive";
    body = (
      <span>
        {label}: refused. {state.reason ?? "No reason given."}
      </span>
    );
  } else if (state?.phase === "failed") {
    tone = "border-destructive/30 bg-destructive/10 text-destructive";
    body = (
      <span>
        {label}: failed. {state.reason}
      </span>
    );
  }
  return (
    <div aria-live="polite" data-testid={testId} role="status">
      {body ? (
        <p
          className={cn(
            "flex items-center gap-2 rounded-lg border px-3 py-2 text-xs",
            tone,
            className,
          )}
          data-phase={state?.phase}
        >
          {body}
        </p>
      ) : null}
    </div>
  );
}

export function OlympusDetailSection({
  children,
  title,
}: {
  children: React.ReactNode;
  title: string;
}) {
  return (
    <section className="space-y-2">
      <h3 className="text-sm font-semibold text-foreground">{title}</h3>
      {children}
    </section>
  );
}

export function OlympusEmptyValue({ children }: { children: React.ReactNode }) {
  return <p className="text-xs text-muted-foreground">{children}</p>;
}
