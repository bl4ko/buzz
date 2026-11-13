import * as React from "react";
import {
  Ban,
  Check,
  CircleAlert,
  Clock,
  Hourglass,
  type LucideIcon,
  ShieldAlert,
  X,
} from "lucide-react";

import {
  clearOlympusRequestState,
  getOlympusRequestState,
  useOlympusRequestState,
  useOlympusRequestVersion,
} from "@/features/agents/lib/olympusChangeRequests";
import {
  decodeOlympusDiffValue,
  isOlympusLongDiff,
  isOlympusProposalOpen,
  type OlympusDiffValue,
  type OlympusProposal,
  type OlympusProposalDiff,
  type OlympusProposalPhase,
  olympusLineDiff,
  olympusProposalKey,
  olympusProposalStatus,
} from "@/features/agents/lib/olympusProposals";
import {
  type OlympusAgentsState,
  useOlympusAgents,
} from "@/features/agents/useOlympusAgents";
import { cn } from "@/shared/lib/cn";
import { useNow } from "@/shared/lib/useNow";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/shared/ui/alert-dialog";
import { Badge, type BadgeProps } from "@/shared/ui/badge";
import { Button } from "@/shared/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/shared/ui/dialog";
import { Textarea } from "@/shared/ui/textarea";
import { OlympusRequestStatus } from "./OlympusAgentParts";

type SubmitChange = OlympusAgentsState["submitChange"];

export const OLYMPUS_REJECT_REASON_MAX_BYTES = 1_000;

const PHASE_STYLES: Record<
  OlympusProposalPhase,
  { variant: BadgeProps["variant"]; Icon: LucideIcon }
> = {
  pending: { variant: "warning", Icon: Clock },
  applied: { variant: "success", Icon: Check },
  rejected: { variant: "outline", Icon: X },
  refused: { variant: "destructive", Icon: Ban },
  failed: { variant: "destructive", Icon: CircleAlert },
  expired: { variant: "secondary", Icon: Hourglass },
};

export function useNowSeconds() {
  return Math.floor(useNow(30_000) / 1_000);
}

export function formatOlympusSpan(seconds: number) {
  const value = Math.max(0, seconds);
  if (value < 60) return "less than a minute";
  if (value < 3_600) return `${Math.floor(value / 60)}m`;
  if (value < 86_400) return `${Math.floor(value / 3_600)}h`;
  return `${Math.floor(value / 86_400)}d`;
}

function timeLine(proposal: OlympusProposal, now: number) {
  const age = `Proposed ${formatOlympusSpan(now - proposal.createdAt)} ago`;
  if (proposal.phase !== "pending") return age;
  return proposal.expiresAt > now
    ? `${age} · expires in ${formatOlympusSpan(proposal.expiresAt - now)}`
    : `${age} · expired ${formatOlympusSpan(now - proposal.expiresAt)} ago`;
}

function absoluteTime(seconds: number) {
  return new Date(seconds * 1_000).toLocaleString();
}

export function olympusUtf8Length(value: string) {
  return new TextEncoder().encode(value).length;
}

export function OlympusProposalStatusBadge({
  status,
}: {
  status: OlympusProposalPhase;
}) {
  const { Icon, variant } = PHASE_STYLES[status];
  return (
    <Badge
      className="gap-1"
      data-testid="olympus-proposal-phase"
      variant={variant}
    >
      <Icon aria-hidden className="-mt-0.5 h-3 w-3" />
      {status}
    </Badge>
  );
}

export function useVisibleOlympusProposals(
  proposals: readonly OlympusProposal[],
  requesterKey?: string,
) {
  const now = useNowSeconds();
  useOlympusRequestVersion();
  return proposals.filter(
    (proposal) =>
      (requesterKey === undefined || proposal.requesterKey === requesterKey) &&
      (isOlympusProposalOpen(proposal, now) ||
        getOlympusRequestState(olympusProposalKey(proposal)) !== null),
  );
}

function DiffValue({
  marker,
  value,
}: {
  marker: "-" | "+";
  value: OlympusDiffValue | null;
}) {
  const Tag = marker === "-" ? "del" : "ins";
  return (
    <Tag
      className={cn(
        "rounded px-1 no-underline",
        marker === "-"
          ? "bg-destructive/10 text-destructive"
          : "bg-emerald-500/10 text-emerald-700 dark:text-emerald-300",
      )}
    >
      <span aria-hidden className="select-none pr-1 opacity-70">
        {marker}
      </span>
      {value ? (
        `${value.text}${value.truncated ? "…" : ""}`
      ) : (
        <span className="italic opacity-80">unset</span>
      )}
    </Tag>
  );
}

const LINE_STYLES = {
  same: { marker: " ", className: "text-muted-foreground" },
  del: {
    marker: "-",
    className: "bg-destructive/10 text-destructive",
  },
  add: {
    marker: "+",
    className: "bg-emerald-500/10 text-emerald-700 dark:text-emerald-300",
  },
} as const;

function LineDiff({
  entry,
  from,
  to,
}: {
  entry: OlympusProposalDiff;
  from: OlympusDiffValue | null;
  to: OlympusDiffValue | null;
}) {
  const lines = React.useMemo(
    () => olympusLineDiff(from?.text ?? null, to?.text ?? null),
    [from, to],
  );
  const added = lines.filter((line) => line.type === "add").length;
  const removed = lines.filter((line) => line.type === "del").length;
  return (
    <li className="overflow-hidden rounded-lg border border-border/60 bg-background/60">
      <div className="flex items-center justify-between gap-2 border-b border-border/60 bg-muted/40 px-3 py-1.5">
        <span className="truncate text-foreground">{entry.path}</span>
        <span className="shrink-0 text-2xs text-muted-foreground">
          {from === null ? "set" : to === null ? "unset" : "changed"} ·{" "}
          <span className="text-emerald-700 dark:text-emerald-300">
            +{added}
          </span>{" "}
          <span className="text-destructive">-{removed}</span>
          {from?.truncated || to?.truncated ? " · cut by the operator" : ""}
        </span>
      </div>
      <div
        className="max-h-72 overflow-auto py-1"
        data-testid="olympus-proposal-line-diff"
      >
        {lines.map((line, index) => {
          const style = LINE_STYLES[line.type];
          return (
            <div
              className={cn("flex px-1", style.className)}
              data-line={line.type}
              // biome-ignore lint/suspicious/noArrayIndexKey: lines are positional
              key={index}
            >
              <span
                aria-hidden
                className="w-5 shrink-0 select-none text-center opacity-70"
              >
                {style.marker}
              </span>
              <span className="sr-only">
                {line.type === "add"
                  ? "added: "
                  : line.type === "del"
                    ? "removed: "
                    : ""}
              </span>
              <span className="min-w-0 flex-1 whitespace-pre-wrap break-words pr-2">
                {line.text || " "}
              </span>
            </div>
          );
        })}
      </div>
    </li>
  );
}

export function OlympusProposalDiffList({
  proposal,
}: {
  proposal: Pick<OlympusProposal, "diff" | "diffTruncated">;
}) {
  if (proposal.diff.length === 0) {
    return (
      <p className="text-xs text-muted-foreground">
        {proposal.diffTruncated
          ? "The change is too large to show here."
          : "No field changes."}
      </p>
    );
  }
  return (
    <ul
      className="space-y-1.5 font-mono text-xs"
      data-testid="olympus-proposal-diff"
    >
      {proposal.diff.map((entry) => {
        const from = decodeOlympusDiffValue(entry.from);
        const to = decodeOlympusDiffValue(entry.to);
        if (isOlympusLongDiff(from, to)) {
          return (
            <LineDiff entry={entry} from={from} key={entry.path} to={to} />
          );
        }
        return (
          <li
            className="flex flex-wrap items-baseline gap-x-1.5 gap-y-1 break-all rounded-lg bg-muted/40 px-3 py-1.5"
            key={entry.path}
          >
            <span className="text-foreground">{entry.path}</span>
            <DiffValue marker="-" value={from} />
            <span aria-hidden className="text-muted-foreground">
              →
            </span>
            <DiffValue marker="+" value={to} />
          </li>
        );
      })}
    </ul>
  );
}

export function OlympusRejectDialog({
  onOpenChange,
  onReject,
  open,
  proposal,
}: {
  onOpenChange: (open: boolean) => void;
  onReject: (reason: string) => void;
  open: boolean;
  proposal: OlympusProposal;
}) {
  const [reason, setReason] = React.useState("");
  const reasonId = React.useId();
  const bytes = olympusUtf8Length(reason.trim());
  const tooLong = bytes > OLYMPUS_REJECT_REASON_MAX_BYTES;
  React.useEffect(() => {
    if (!open) setReason("");
  }, [open]);
  const submit = (event: { preventDefault: () => void }) => {
    event.preventDefault();
    if (tooLong) return;
    onReject(reason.trim());
    onOpenChange(false);
  };
  return (
    <Dialog onOpenChange={onOpenChange} open={open}>
      <DialogContent className="max-w-lg" data-testid="olympus-reject-dialog">
        <form className="grid gap-4" onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>Reject this proposal?</DialogTitle>
            <DialogDescription>
              {proposal.requester} asked to {proposal.operation}{" "}
              {proposal.target.kind} {proposal.target.name} in workspace{" "}
              {proposal.workspace}. The reason goes back to the requester.
            </DialogDescription>
          </DialogHeader>
          <div className="grid gap-1.5">
            <label
              className="text-sm font-medium text-foreground"
              htmlFor={reasonId}
            >
              Reason{" "}
              <span className="font-normal text-muted-foreground">
                (optional)
              </span>
            </label>
            <Textarea
              autoFocus
              className="min-h-28 resize-y"
              data-testid="olympus-reject-reason"
              id={reasonId}
              maxLength={OLYMPUS_REJECT_REASON_MAX_BYTES}
              onChange={(event) => setReason(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
                  submit(event);
                }
              }}
              placeholder="Why not? For example: keep Argus running during the backup window."
              value={reason}
            />
            <p
              aria-live="polite"
              className={cn(
                "text-right text-2xs tabular-nums",
                tooLong ? "text-destructive" : "text-muted-foreground",
              )}
              data-testid="olympus-reject-counter"
            >
              {bytes}/{OLYMPUS_REJECT_REASON_MAX_BYTES}
            </p>
          </div>
          <DialogFooter>
            <Button
              onClick={() => onOpenChange(false)}
              type="button"
              variant="outline"
            >
              Cancel
            </Button>
            <Button disabled={tooLong} type="submit" variant="destructive">
              <X />
              Reject proposal
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

export function OlympusProposalCard({
  className,
  proposal,
  submitChange,
}: {
  className?: string;
  proposal: OlympusProposal;
  submitChange: SubmitChange;
}) {
  const now = useNowSeconds();
  const key = olympusProposalKey(proposal);
  const request = useOlympusRequestState(key);
  const [confirming, setConfirming] = React.useState(false);
  const [rejecting, setRejecting] = React.useState(false);
  const open = isOlympusProposalOpen(proposal, now);
  const status = olympusProposalStatus(proposal, now);
  const busy = request?.phase === "pending";
  const highRisk = proposal.highRisk.length > 0;
  const titleId = React.useId();
  const target = proposal.target;
  const decidedAt = proposal.result?.at ?? null;

  const decide = (
    action: "approve" | "reject",
    options: { confirmed?: boolean; reason?: string } = {},
  ) => {
    void submitChange(
      key,
      { operator: proposal.author, workspace: proposal.workspace, agent: null },
      {
        action,
        proposal: proposal.name,
        digest: proposal.digest,
        ...(options.confirmed ? { highRisk: true as const } : {}),
        ...(options.reason ? { reason: options.reason } : {}),
      },
    );
  };

  return (
    <section
      aria-labelledby={titleId}
      className={cn(
        "space-y-3 rounded-2xl border bg-card px-4 py-3 text-sm shadow-xs",
        highRisk && open ? "border-destructive/50" : "border-border/70",
        className,
      )}
      data-phase={status}
      data-testid={`olympus-proposal-${proposal.name}`}
    >
      <header className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0 space-y-0.5">
          <h3 className="font-semibold text-foreground" id={titleId}>
            {proposal.requester} proposes to {proposal.operation} {target.kind}{" "}
            {target.name}
          </h3>
          <p className="text-xs text-muted-foreground">
            Workspace {proposal.workspace}
            {target.namespace ? ` · namespace ${target.namespace}` : ""} ·{" "}
            <span title={absoluteTime(proposal.createdAt)}>
              {timeLine(proposal, now)}
            </span>
          </p>
        </div>
        <div className="flex items-center gap-1.5">
          {highRisk ? (
            <Badge
              className="gap-1"
              data-testid="olympus-proposal-high-risk"
              variant="destructive"
            >
              <ShieldAlert aria-hidden className="-mt-0.5 h-3 w-3" />
              High risk
            </Badge>
          ) : null}
          <OlympusProposalStatusBadge status={status} />
          {!open && request && !busy ? (
            <Button
              aria-label={`Dismiss proposal ${proposal.name}`}
              onClick={() => clearOlympusRequestState(key)}
              size="icon-xs"
              type="button"
              variant="ghost"
            >
              <X />
            </Button>
          ) : null}
        </div>
      </header>

      {highRisk ? (
        <p className="flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-xs text-destructive">
          <ShieldAlert aria-hidden className="mt-px h-4 w-4 shrink-0" />
          <span>High risk: {proposal.highRisk.join(", ")}</span>
        </p>
      ) : null}

      <p
        className="whitespace-pre-wrap break-words text-foreground"
        data-testid="olympus-proposal-reason"
      >
        {proposal.reason}
      </p>

      <OlympusProposalDiffList proposal={proposal} />

      {open ? (
        <div className="flex flex-wrap items-center gap-2">
          <Button
            disabled={busy}
            onClick={() => (highRisk ? setConfirming(true) : decide("approve"))}
            size="sm"
            type="button"
            variant={highRisk ? "destructive" : "default"}
          >
            <Check />
            Approve
          </Button>
          <Button
            disabled={busy}
            onClick={() => setRejecting(true)}
            size="sm"
            type="button"
            variant="outline"
          >
            <X />
            Reject
          </Button>
        </div>
      ) : proposal.result?.reason || decidedAt !== null ? (
        <p
          className="flex flex-wrap items-baseline gap-x-2 gap-y-0.5 rounded-lg bg-muted/40 px-3 py-2 text-xs text-muted-foreground"
          data-testid="olympus-proposal-result"
        >
          {proposal.result?.reason ? (
            <span className="whitespace-pre-wrap break-words text-foreground">
              {proposal.result.reason}
            </span>
          ) : null}
          {decidedAt !== null ? (
            <span title={absoluteTime(decidedAt)}>
              Decided {formatOlympusSpan(now - decidedAt)} ago
            </span>
          ) : null}
        </p>
      ) : null}

      <OlympusRequestStatus
        state={request}
        testId={`olympus-proposal-request-${proposal.name}`}
      />

      <OlympusRejectDialog
        onOpenChange={setRejecting}
        onReject={(reason) => decide("reject", { reason })}
        open={rejecting}
        proposal={proposal}
      />

      <AlertDialog onOpenChange={setConfirming} open={confirming}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Approve a high-risk change?</AlertDialogTitle>
            <AlertDialogDescription>
              {proposal.requester} asks to {proposal.operation} {target.kind}{" "}
              {target.name} in workspace {proposal.workspace}. High risk:{" "}
              {proposal.highRisk.join(", ")}. Hephaestus applies the change when
              you approve.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel asChild>
              <Button type="button" variant="outline">
                Cancel
              </Button>
            </AlertDialogCancel>
            <AlertDialogAction asChild>
              <Button
                onClick={() => decide("approve", { confirmed: true })}
                type="button"
                variant="destructive"
              >
                Approve high-risk change
              </Button>
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </section>
  );
}

export function OlympusDmProposals({ peer }: { peer: string }) {
  const olympus = useOlympusAgents();
  const proposals = useVisibleOlympusProposals(olympus.proposals, peer);
  if (proposals.length === 0) return null;
  return (
    <div
      className="relative z-10 mx-5 mb-2 max-h-[40vh] space-y-2 overflow-y-auto"
      data-testid="olympus-dm-proposals"
    >
      {proposals.map((proposal) => (
        <OlympusProposalCard
          key={olympusProposalKey(proposal)}
          proposal={proposal}
          submitChange={olympus.submitChange}
        />
      ))}
    </div>
  );
}
