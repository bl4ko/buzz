import * as React from "react";
import {
  Check,
  ChevronDown,
  CircleCheck,
  CircleDashed,
  CircleDot,
  Clock,
  Crown,
  Lock,
  Minus,
  Pause,
  X,
} from "lucide-react";

import type { OlympusAgent } from "@/features/agents/lib/olympusAgents";
import { olympusAgentLabel } from "@/features/agents/lib/olympusAgents";
import { cn } from "@/shared/lib/cn";
import { Button } from "@/shared/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuTrigger,
} from "@/shared/ui/dropdown-menu";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/shared/ui/tooltip";
import { UserAvatar } from "@/shared/ui/UserAvatar";

const CHIP =
  "inline-flex shrink-0 items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium leading-5";

const TONES = {
  good: "bg-emerald-500/12 text-emerald-800 dark:bg-emerald-400/12 dark:text-emerald-300",
  info: "bg-sky-500/12 text-sky-800 dark:bg-sky-400/12 dark:text-sky-300",
  warn: "bg-amber-500/15 text-amber-800 dark:bg-amber-400/12 dark:text-amber-300",
  bad: "bg-destructive/12 text-destructive dark:text-red-300",
  muted: "bg-muted text-muted-foreground",
} as const;

type Tone = keyof typeof TONES;

export function OlympusChip({
  children,
  className,
  icon: Icon,
  tone = "muted",
  ...props
}: React.HTMLAttributes<HTMLSpanElement> & {
  icon?: React.ComponentType<{ className?: string; "aria-hidden"?: boolean }>;
  tone?: Tone;
}) {
  return (
    <span className={cn(CHIP, TONES[tone], className)} {...props}>
      {Icon ? <Icon aria-hidden className="h-3.5 w-3.5" /> : null}
      {children}
    </span>
  );
}

const PHASES: Record<
  string,
  { tone: Tone; icon: React.ComponentType<{ className?: string }> }
> = {
  Online: { tone: "good", icon: CircleCheck },
  Ready: { tone: "info", icon: CircleDot },
  Enrolled: { tone: "info", icon: CircleDashed },
  Pending: { tone: "warn", icon: Clock },
  Suspended: { tone: "muted", icon: Pause },
};

export function OlympusPhase({ phase }: { phase: string }) {
  const look = PHASES[phase] ?? { tone: "muted" as Tone, icon: CircleDashed };
  return (
    <OlympusChip data-phase={phase} icon={look.icon} tone={look.tone}>
      {phase}
    </OlympusChip>
  );
}

const RESULTS: Record<
  string,
  {
    label: string;
    tone: Tone;
    icon: React.ComponentType<{ className?: string }>;
  }
> = {
  Succeeded: { label: "Succeeded", tone: "good", icon: Check },
  NoWork: { label: "No work", tone: "muted", icon: Minus },
  Failed: { label: "Failed", tone: "bad", icon: X },
};

export function OlympusRunResult({ result }: { result: string | null }) {
  if (!result) {
    return <span className="text-xs text-muted-foreground">Never ran</span>;
  }
  const look = RESULTS[result] ?? {
    label: result,
    tone: "muted" as Tone,
    icon: CircleDashed,
  };
  return (
    <OlympusChip data-result={result} icon={look.icon} tone={look.tone}>
      {look.label}
    </OlympusChip>
  );
}

export function OlympusMasterChip(
  props: React.HTMLAttributes<HTMLSpanElement>,
) {
  return (
    <OlympusChip icon={Crown} tone="warn" {...props}>
      Master
    </OlympusChip>
  );
}

export function OlympusGitLock({ field }: { field: string }) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <span
          aria-label={`${field} is set in gitops-home`}
          className="inline-flex items-center text-muted-foreground"
          data-testid={`olympus-lock-${field}`}
          role="img"
        >
          <Lock aria-hidden className="h-3.5 w-3.5" />
        </span>
      </TooltipTrigger>
      <TooltipContent>Set in gitops-home. Change it there.</TooltipContent>
    </Tooltip>
  );
}

export function OlympusAgentAvatar({
  agent,
  size = "md",
}: {
  agent: OlympusAgent;
  size?: "xs" | "sm" | "md";
}) {
  return (
    <UserAvatar
      avatarUrl={agent.spec.profile?.picture ?? null}
      displayName={olympusAgentLabel(agent)}
      size={size}
    />
  );
}

export function formatOlympusAgo(value: string | number | null): string | null {
  if (value === null) return null;
  const millis = typeof value === "number" ? value * 1_000 : Date.parse(value);
  if (Number.isNaN(millis)) return typeof value === "string" ? value : null;
  const seconds = Math.max(0, Math.floor((Date.now() - millis) / 1_000));
  if (seconds < 60) return "just now";
  if (seconds < 3_600) return `${Math.floor(seconds / 60)} min ago`;
  if (seconds < 86_400) return `${Math.floor(seconds / 3_600)} h ago`;
  return `${Math.floor(seconds / 86_400)} d ago`;
}

export function formatOlympusIn(date: Date | null): string | null {
  if (!date) return null;
  const minutes = Math.max(
    0,
    Math.round((date.getTime() - Date.now()) / 60_000),
  );
  if (minutes < 1) return "in less than 1 min";
  if (minutes < 60) return `in ${minutes} min`;
  if (minutes < 1_440) {
    const hours = Math.floor(minutes / 60);
    const rest = minutes % 60;
    return rest ? `in ${hours} h ${rest} min` : `in ${hours} h`;
  }
  return `in ${Math.floor(minutes / 1_440)} d`;
}

export function formatOlympusDate(date: Date | string | number | null) {
  if (date === null) return null;
  const value =
    typeof date === "number" ? new Date(date * 1_000) : new Date(date);
  if (Number.isNaN(value.getTime())) return null;
  return value.toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  });
}

export function OlympusCard({
  action,
  children,
  className,
  description,
  testId,
  title,
}: {
  action?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
  description?: React.ReactNode;
  testId?: string;
  title: React.ReactNode;
}) {
  const headingId = React.useId();
  return (
    <section
      aria-labelledby={headingId}
      className={cn(
        "overflow-hidden rounded-xl border border-border/70 bg-card/60",
        className,
      )}
      data-testid={testId}
    >
      <div className="flex flex-wrap items-start justify-between gap-3 px-4 pt-3.5 pb-2">
        <div className="min-w-0 space-y-0.5">
          <h2
            className="flex items-center gap-2 text-sm font-semibold text-foreground"
            id={headingId}
          >
            {title}
          </h2>
          {description ? (
            <p className="text-xs text-muted-foreground">{description}</p>
          ) : null}
        </div>
        {action ? (
          <div className="flex flex-wrap items-center gap-2">{action}</div>
        ) : null}
      </div>
      <div className="px-4 pb-4">{children}</div>
    </section>
  );
}

export function OlympusFacts({ children }: { children: React.ReactNode }) {
  return (
    <dl className="grid gap-x-6 gap-y-3 sm:grid-cols-2 xl:grid-cols-3">
      {children}
    </dl>
  );
}

export function OlympusFact({
  children,
  label,
  locked,
}: {
  children: React.ReactNode;
  label: string;
  locked?: boolean;
}) {
  return (
    <div className="min-w-0 space-y-0.5">
      <dt className="flex items-center gap-1.5 text-xs text-muted-foreground">
        {label}
        {locked ? <OlympusGitLock field={label} /> : null}
      </dt>
      <dd className="min-w-0 break-words text-sm text-foreground">
        {children}
      </dd>
    </div>
  );
}

export function OlympusNone({ children }: { children: React.ReactNode }) {
  return <span className="text-sm text-muted-foreground">{children}</span>;
}

export function OlympusEmptyState({
  children,
  icon: Icon,
  testId,
  title,
}: {
  children?: React.ReactNode;
  icon: React.ComponentType<{ className?: string; "aria-hidden"?: boolean }>;
  testId?: string;
  title: string;
}) {
  return (
    <div
      className="mx-auto flex max-w-md flex-col items-center gap-3 rounded-xl border border-dashed border-border/80 px-6 py-10 text-center"
      data-testid={testId}
    >
      <span className="flex h-10 w-10 items-center justify-center rounded-full bg-muted text-muted-foreground">
        <Icon aria-hidden className="h-5 w-5" />
      </span>
      <h2 className="text-sm font-semibold text-foreground">{title}</h2>
      {children ? (
        <div className="space-y-2 text-sm text-muted-foreground">
          {children}
        </div>
      ) : null}
    </div>
  );
}

export function OlympusSelect({
  className,
  disabled,
  id,
  label,
  onChange,
  options,
  placeholder = "Choose",
  value,
}: {
  className?: string;
  disabled?: boolean;
  id?: string;
  label: string;
  onChange: (value: string) => void;
  options: readonly { value: string; label: string }[];
  placeholder?: string;
  value: string;
}) {
  const current = options.find((option) => option.value === value);
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild disabled={disabled}>
        <Button
          aria-label={`${label}: ${current?.label ?? placeholder}`}
          className={cn("w-full justify-between font-normal", className)}
          id={id}
          type="button"
          variant="outline"
        >
          <span
            className={cn("truncate", current ? "" : "text-muted-foreground")}
          >
            {current?.label ?? placeholder}
          </span>
          <ChevronDown aria-hidden className="h-4 w-4 opacity-60" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent
        align="start"
        className="max-h-72 min-w-[var(--radix-dropdown-menu-trigger-width)] overflow-y-auto"
      >
        <DropdownMenuRadioGroup onValueChange={onChange} value={value}>
          {options.map((option) => (
            <DropdownMenuRadioItem key={option.value} value={option.value}>
              {option.label}
            </DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
