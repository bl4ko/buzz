import * as React from "react";
import { MountainSnow, RadioTower } from "lucide-react";

import { useAppNavigation } from "@/app/navigation/useAppNavigation";
import { useManagedAgentsQuery } from "@/features/agents/hooks";
import { useOlympusAgents } from "@/features/agents/useOlympusAgents";
import { TopChromeInsetHeader } from "@/shared/layout/TopChromeInsetHeader";
import { Skeleton } from "@/shared/ui/skeleton";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/shared/ui/tabs";
import { ViewLoadingFallback } from "@/shared/ui/ViewLoadingFallback";
import { type OlympusTab, visibleOlympusTabs } from "../lib/olympusTabs";
import { listOlympusSchedules } from "../lib/olympusSchedules";
import { useOlympusPendingProposalCount } from "../useOlympusPendingProposalCount";
import { OlympusProposalsTab, OlympusUsageTab } from "./olympusMounts";
import { OlympusAgentsTab } from "./OlympusAgentsTab";
import {
  OlympusProvidersTab,
  OlympusWorkspacesTab,
} from "./OlympusInventoryTabs";
import { OlympusEmptyState } from "./OlympusParts";
import { OlympusSchedulesTab } from "./OlympusSchedulesTab";

const AgentsScreen = React.lazy(async () => {
  const module = await import("@/features/agents/ui/AgentsScreen");
  return { default: module.AgentsScreen };
});

function summary(workspaces: number, agents: number, failing: number): string {
  const parts = [
    `${workspaces} ${workspaces === 1 ? "workspace" : "workspaces"}`,
    `${agents} ${agents === 1 ? "agent" : "agents"}`,
  ];
  if (failing > 0) {
    parts.push(`${failing} failed ${failing === 1 ? "schedule" : "schedules"}`);
  }
  return parts.join(" · ");
}

export function OlympusPage({ tab }: { tab: OlympusTab }) {
  const olympus = useOlympusAgents();
  const { goOlympus } = useAppNavigation();
  const pending = useOlympusPendingProposalCount();
  const localAgents = useManagedAgentsQuery().data?.length ?? 0;
  const tabs = visibleOlympusTabs(tab, localAgents > 0);
  const agents = olympus.groups.reduce(
    (count, group) => count + group.agents.length,
    0,
  );
  const failing = React.useMemo(
    () =>
      listOlympusSchedules(olympus.groups, Date.now()).filter(
        (row) => row.failed,
      ).length,
    [olympus.groups],
  );
  const empty =
    !olympus.isLoading && !olympus.error && olympus.groups.length === 0;

  return (
    <section
      aria-label="Olympus"
      className="flex h-full min-h-0 min-w-0 flex-1 flex-col"
      data-testid="olympus-page"
    >
      <TopChromeInsetHeader flush>
        <div className="flex flex-wrap items-center gap-x-3 gap-y-1 px-4 py-3">
          <h1 className="flex items-center gap-2 text-base font-semibold">
            <MountainSnow aria-hidden className="h-4 w-4" />
            Olympus
          </h1>
          {!empty && !olympus.isLoading ? (
            <p
              className="text-xs text-muted-foreground"
              data-testid="olympus-summary"
            >
              {summary(olympus.groups.length, agents, failing)}
            </p>
          ) : null}
        </div>
      </TopChromeInsetHeader>
      <Tabs
        className="flex min-h-0 flex-1 flex-col"
        onValueChange={(value) => void goOlympus(value)}
        value={tab}
      >
        <div className="border-b border-border/60 px-4 py-2">
          <TabsList
            aria-label="Olympus sections"
            className="h-8 max-w-full justify-start overflow-x-auto [scrollbar-width:none]"
          >
            {tabs.map((item) => (
              <TabsTrigger
                className="gap-1.5 px-2 text-xs"
                data-testid={`olympus-tab-${item.id}`}
                key={item.id}
                value={item.id}
              >
                {item.label}
                {item.id === "proposals" && pending > 0 ? (
                  <span className="rounded-full bg-primary/15 px-1.5 text-2xs font-semibold text-primary">
                    {pending}
                    <span className="sr-only"> pending</span>
                  </span>
                ) : null}
              </TabsTrigger>
            ))}
          </TabsList>
        </div>
        {tab === "local" ? (
          <TabsContent
            className="mt-0 flex min-h-0 flex-1 flex-col"
            data-testid="olympus-local-agents"
            value="local"
          >
            <React.Suspense fallback={<ViewLoadingFallback kind="agents" />}>
              <AgentsScreen embedded />
            </React.Suspense>
          </TabsContent>
        ) : (
          <div className="min-h-0 flex-1 overflow-y-auto">
            <div className="mx-auto w-full max-w-5xl px-4 py-5">
              {olympus.error ? (
                <p className="mb-4 rounded-lg border border-destructive/30 bg-destructive/10 px-4 py-3 text-sm text-destructive">
                  Couldn’t load Olympus state. {olympus.error.message}
                </p>
              ) : null}
              {olympus.isLoading ? (
                <div className="space-y-3" data-testid="olympus-loading">
                  <Skeleton className="h-24 w-full rounded-xl" />
                  <Skeleton className="h-24 w-full rounded-xl" />
                </div>
              ) : empty && tab !== "proposals" && tab !== "usage" ? (
                <OlympusNoState />
              ) : (
                <>
                  <TabsContent className="mt-0" value="agents">
                    <OlympusAgentsTab />
                  </TabsContent>
                  <TabsContent className="mt-0" value="schedules">
                    <OlympusSchedulesTab />
                  </TabsContent>
                  <TabsContent className="mt-0" value="proposals">
                    <OlympusProposalsTab />
                  </TabsContent>
                  <TabsContent className="mt-0" value="usage">
                    <OlympusUsageTab />
                  </TabsContent>
                  <TabsContent className="mt-0" value="workspaces">
                    <OlympusWorkspacesTab />
                  </TabsContent>
                  <TabsContent className="mt-0" value="providers">
                    <OlympusProvidersTab />
                  </TabsContent>
                </>
              )}
            </div>
          </div>
        )}
      </Tabs>
    </section>
  );
}

function OlympusNoState() {
  return (
    <OlympusEmptyState
      icon={RadioTower}
      testId="olympus-no-state"
      title="No Olympus state from this relay"
    >
      <p>
        Hephaestus publishes the agent and workspace state (kinds 30190 and
        30191) only to the owner key of the agents.
      </p>
      <p>
        Check that this community is the Olympus relay and that you use the
        owner identity.
      </p>
    </OlympusEmptyState>
  );
}
