import { createRootRoute } from "@tanstack/react-router";

import { AppShell } from "@/app/AppShell";
import { OlympusAgentsProvider } from "@/features/agents/useOlympusAgents";
import { HuddlePresenceProvider } from "@/features/huddle/HuddlePresenceContext";
import { UserStatusLookupProvider } from "@/features/user-status/UserStatusLookupContext";

function RootRoute() {
  return (
    <HuddlePresenceProvider>
      <UserStatusLookupProvider>
        <OlympusAgentsProvider>
          <AppShell />
        </OlympusAgentsProvider>
      </UserStatusLookupProvider>
    </HuddlePresenceProvider>
  );
}

export const Route = createRootRoute({
  component: RootRoute,
});
