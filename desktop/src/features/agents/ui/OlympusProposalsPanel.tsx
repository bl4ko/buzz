import * as React from "react";

import {
  countOlympusProposals,
  countPendingOlympusProposals,
  filterOlympusProposals,
  nextOlympusProposalExpiry,
  OLYMPUS_PROPOSAL_FILTERS,
  type OlympusProposal,
  type OlympusProposalFilter,
  olympusProposalKey,
} from "@/features/agents/lib/olympusProposals";
import {
  type OlympusAgentsState,
  useOlympusAgents,
} from "@/features/agents/useOlympusAgents";
import { cn } from "@/shared/lib/cn";
import { Spinner } from "@/shared/ui/spinner";
import { Toggle } from "@/shared/ui/toggle";
import { OlympusProposalCard, useNowSeconds } from "./OlympusProposalCard";

const MAX_TIMER_MS = 2_147_483_647;

const FILTER_LABELS: Record<OlympusProposalFilter, string> = {
  pending: "Pending",
  applied: "Applied",
  rejected: "Rejected",
  refused: "Refused",
  failed: "Failed",
  expired: "Expired",
  all: "All",
};

function nowSeconds() {
  return Math.floor(Date.now() / 1_000);
}

export function useOlympusProposalExpiryClock(
  proposals: readonly OlympusProposal[],
): number {
  const [now, setNow] = React.useState(nowSeconds);
  const next = nextOlympusProposalExpiry(proposals, now);
  React.useEffect(() => {
    if (next === null) return;
    const timer = setTimeout(
      () => setNow(nowSeconds()),
      Math.min(MAX_TIMER_MS, Math.max(0, next * 1_000 - Date.now()) + 250),
    );
    return () => clearTimeout(timer);
  }, [next]);
  return now;
}

export function usePendingOlympusProposalCount(
  requesterKey?: string | null,
): number {
  const { proposals } = useOlympusAgents();
  const now = useOlympusProposalExpiryClock(proposals);
  return countPendingOlympusProposals(proposals, now, requesterKey);
}

export function OlympusProposalsList({
  filter,
  now,
  onFilterChange,
  proposals,
  submitChange,
}: {
  filter: OlympusProposalFilter;
  now: number;
  onFilterChange: (filter: OlympusProposalFilter) => void;
  proposals: readonly OlympusProposal[];
  submitChange: OlympusAgentsState["submitChange"];
}) {
  const counts = countOlympusProposals(proposals, now);
  const visible = filterOlympusProposals(proposals, filter, now);
  return (
    <div className="space-y-4" data-testid="olympus-proposals-panel">
      <fieldset
        aria-label="Filter proposals"
        className="flex flex-wrap items-center gap-1.5"
        data-testid="olympus-proposal-filters"
      >
        {OLYMPUS_PROPOSAL_FILTERS.map((option) => (
          <Toggle
            aria-label={`${FILTER_LABELS[option]}, ${counts[option]}`}
            className="h-7 gap-1.5 rounded-full px-3 text-xs"
            data-testid={`olympus-proposal-filter-${option}`}
            key={option}
            onPressedChange={(pressed) => {
              if (pressed) onFilterChange(option);
            }}
            pressed={filter === option}
            size="sm"
            variant="outline"
          >
            {FILTER_LABELS[option]}
            <span
              aria-hidden
              className={cn(
                "min-w-4 rounded-full px-1 text-center text-2xs tabular-nums",
                option === "pending" && counts.pending > 0
                  ? "bg-amber-500/20 font-semibold text-amber-700 dark:text-amber-300"
                  : "text-muted-foreground",
              )}
            >
              {counts[option]}
            </span>
          </Toggle>
        ))}
      </fieldset>

      {proposals.length === 0 ? (
        <div
          className="rounded-2xl border border-dashed border-border/70 px-6 py-10 text-center"
          data-testid="olympus-proposals-empty"
        >
          <p className="text-sm font-medium text-foreground">No proposals</p>
          <p className="mt-1 text-xs text-muted-foreground">
            Agents propose changes through Zeus. Hephaestus keeps decided
            proposals for 7 days.
          </p>
        </div>
      ) : visible.length === 0 ? (
        <p
          className="rounded-2xl border border-dashed border-border/70 px-6 py-8 text-center text-sm text-muted-foreground"
          data-testid="olympus-proposals-empty"
        >
          No {FILTER_LABELS[filter].toLowerCase()} proposals.
        </p>
      ) : (
        <ul className="space-y-3" data-testid="olympus-proposals-list">
          {visible.map((proposal) => (
            <li key={olympusProposalKey(proposal)}>
              <OlympusProposalCard
                proposal={proposal}
                submitChange={submitChange}
              />
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

export function OlympusProposalsPanel() {
  const olympus = useOlympusAgents();
  const now = useNowSeconds();
  const [chosen, setChosen] = React.useState<OlympusProposalFilter | null>(
    null,
  );
  const hasPending = React.useMemo(
    () => countPendingOlympusProposals(olympus.proposals, now) > 0,
    [olympus.proposals, now],
  );
  const filter = chosen ?? (hasPending ? "pending" : "all");

  if (olympus.isLoading && olympus.proposals.length === 0) {
    return (
      <div className="flex items-center gap-2 py-8 text-sm text-muted-foreground">
        <Spinner aria-hidden className="h-4 w-4" />
        Loading proposals…
      </div>
    );
  }
  if (olympus.error && olympus.proposals.length === 0) {
    return (
      <p className="rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive">
        Couldn’t load proposals: {olympus.error.message}
      </p>
    );
  }
  return (
    <OlympusProposalsList
      filter={filter}
      now={now}
      onFilterChange={setChosen}
      proposals={olympus.proposals}
      submitChange={olympus.submitChange}
    />
  );
}
