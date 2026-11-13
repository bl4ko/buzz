import * as React from "react";
import { Check, ShieldAlert, X } from "lucide-react";

import {
  getOlympusRequestState,
  clearOlympusRequestState,
  useOlympusRequestState,
  useOlympusRequestVersion,
} from "@/features/agents/lib/olympusChangeRequests";
import {
  isOlympusProposalOpen,
  type OlympusProposal,
  olympusProposalKey,
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
import { OlympusRequestStatus } from "./OlympusAgentParts";

type SubmitChange = OlympusAgentsState["submitChange"];

const PHASE_VARIANTS: Record<string, BadgeProps["variant"]> = {
  pending: "warning",
  applied: "success",
  rejected: "outline",
  refused: "destructive",
  failed: "destructive",
  expired: "secondary",
};

function useNowSeconds() {
  return Math.floor(useNow(30_000) / 1_000);
}

function span(seconds: number) {
  const value = Math.max(0, seconds);
  if (value < 60) return "less than a minute";
  if (value < 3_600) return `${Math.floor(value / 60)}m`;
  if (value < 86_400) return `${Math.floor(value / 3_600)}h`;
  return `${Math.floor(value / 86_400)}d`;
}

function timeLine(proposal: OlympusProposal, now: number) {
  const age = `Proposed ${span(now - proposal.createdAt)} ago`;
  if (proposal.phase !== "pending") return age;
  return proposal.expiresAt > now
    ? `${age} · expires in ${span(proposal.expiresAt - now)}`
    : `${age} · expired ${span(now - proposal.expiresAt)} ago`;
}

function phaseOf(proposal: OlympusProposal, now: number) {
  return proposal.phase === "pending" && proposal.expiresAt <= now
    ? "expired"
    : proposal.phase;
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
  const open = isOlympusProposalOpen(proposal, now);
  const phase = phaseOf(proposal, now);
  const busy = request?.phase === "pending";
  const highRisk = proposal.highRisk.length > 0;
  const titleId = React.useId();
  const target = proposal.target;

  const decide = (action: "approve" | "reject", confirmed = false) => {
    void submitChange(
      key,
      { operator: proposal.author, workspace: proposal.workspace, agent: null },
      {
        action,
        proposal: proposal.name,
        digest: proposal.digest,
        ...(confirmed ? { highRisk: true as const } : {}),
      },
    );
  };

  return (
    <section
      aria-labelledby={titleId}
      className={cn(
        "space-y-3 rounded-2xl border bg-card px-4 py-3 text-sm shadow-xs",
        highRisk ? "border-destructive/50" : "border-border/70",
        className,
      )}
      data-phase={phase}
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
            {timeLine(proposal, now)}
          </p>
        </div>
        <div className="flex items-center gap-1.5">
          {highRisk ? (
            <Badge
              data-testid="olympus-proposal-high-risk"
              variant="destructive"
            >
              High risk
            </Badge>
          ) : null}
          <Badge variant={PHASE_VARIANTS[phase] ?? "secondary"}>{phase}</Badge>
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

      {proposal.diff.length > 0 ? (
        <ul
          className="max-h-40 space-y-1 overflow-y-auto rounded-lg bg-muted/40 px-3 py-2 font-mono text-xs"
          data-testid="olympus-proposal-diff"
        >
          {proposal.diff.map((entry) => (
            <li className="break-all" key={entry.path}>
              <span className="text-foreground">{entry.path}</span>
              <span className="text-muted-foreground">: </span>
              <span className="text-destructive">{entry.from ?? "unset"}</span>
              <span className="text-muted-foreground"> → </span>
              <span className="text-emerald-600 dark:text-emerald-400">
                {entry.to ?? "unset"}
              </span>
            </li>
          ))}
        </ul>
      ) : (
        <p className="text-xs text-muted-foreground">
          {proposal.diffTruncated
            ? "The change is too large to show here."
            : "No field changes."}
        </p>
      )}

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
            onClick={() => decide("reject")}
            size="sm"
            type="button"
            variant="outline"
          >
            <X />
            Reject
          </Button>
        </div>
      ) : proposal.result?.reason ? (
        <p className="text-xs text-muted-foreground">
          Result: {proposal.result.reason}
        </p>
      ) : null}

      <OlympusRequestStatus
        state={request}
        testId={`olympus-proposal-request-${proposal.name}`}
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
                onClick={() => decide("approve", true)}
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
