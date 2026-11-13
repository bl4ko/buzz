export const OLYMPUS_TABS = [
  { id: "agents", label: "Agents" },
  { id: "schedules", label: "Schedules" },
  { id: "proposals", label: "Proposals" },
  { id: "usage", label: "Usage" },
  { id: "workspaces", label: "Workspaces" },
  { id: "providers", label: "Providers & MCP" },
] as const;

export type OlympusTab = (typeof OLYMPUS_TABS)[number]["id"];

export function parseOlympusTab(value: unknown): OlympusTab {
  return OLYMPUS_TABS.some((tab) => tab.id === value)
    ? (value as OlympusTab)
    : "agents";
}
