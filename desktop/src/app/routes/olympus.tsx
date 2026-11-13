import * as React from "react";
import { createFileRoute } from "@tanstack/react-router";

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
  validateSearch: (search: Record<string, unknown>): { tab?: OlympusTab } => {
    const tab = parseOlympusTab(search.tab);
    return tab === "agents" ? {} : { tab };
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
