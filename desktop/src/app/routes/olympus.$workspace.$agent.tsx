import * as React from "react";
import { createFileRoute } from "@tanstack/react-router";

import { ViewLoadingFallback } from "@/shared/ui/ViewLoadingFallback";

const OlympusAgentPage = React.lazy(async () => {
  const module = await import("@/features/olympus/ui/OlympusAgentPage");
  return { default: module.OlympusAgentPage };
});

export const Route = createFileRoute("/olympus/$workspace/$agent")({
  component: OlympusAgentRouteComponent,
});

function OlympusAgentRouteComponent() {
  const { agent, workspace } = Route.useParams();
  return (
    <React.Suspense fallback={<ViewLoadingFallback kind="agents" />}>
      <OlympusAgentPage agentName={agent} workspaceName={workspace} />
    </React.Suspense>
  );
}
