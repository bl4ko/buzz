export const OLYMPUS_TABS = [
  { id: "agents", label: "Agents" },
  { id: "schedules", label: "Schedules" },
  { id: "proposals", label: "Proposals" },
  { id: "usage", label: "Usage" },
  { id: "workspaces", label: "Workspaces" },
  { id: "providers", label: "Providers & MCP" },
  { id: "local", label: "On this Mac" },
] as const;

export type OlympusTab = (typeof OLYMPUS_TABS)[number]["id"];

export function parseOlympusTab(value: unknown): OlympusTab {
  return OLYMPUS_TABS.some((tab) => tab.id === value)
    ? (value as OlympusTab)
    : "agents";
}

export function visibleOlympusTabs(
  current: OlympusTab,
  hasLocalAgents: boolean,
) {
  return OLYMPUS_TABS.filter(
    (tab) => tab.id !== "local" || hasLocalAgents || current === "local",
  );
}
