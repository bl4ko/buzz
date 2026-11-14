import * as React from "react";
import { createFileRoute } from "@tanstack/react-router";

import {
  type AgentsRouteSearch,
  validateAgentsSearch,
} from "@/features/agents/lib/agentsRouteSearch";
import {
  type OlympusTab,
  parseOlympusTab,
} from "@/features/olympus/lib/olympusTabs";
import { ViewLoadingFallback } from "@/shared/ui/ViewLoadingFallback";

const OlympusPage = React.lazy(async () => {
  const module = await import("@/features/olympus/ui/OlympusPage");
  return { default: module.OlympusPage };
});

export const Route = createFileRoute("/olympus")({
  validateSearch: (
    search: Record<string, unknown>,
  ): { tab?: OlympusTab } & AgentsRouteSearch => {
    const tab = parseOlympusTab(search.tab);
    if (tab === "agents") return {};
    if (tab === "local") return { tab, ...validateAgentsSearch(search) };
    return { tab };
  },
  component: OlympusRouteComponent,
});

function OlympusRouteComponent() {
  const { tab } = Route.useSearch();
  return (
    <React.Suspense fallback={<ViewLoadingFallback kind="agents" />}>
      <OlympusPage tab={tab ?? "agents"} />
    </React.Suspense>
  );
}
