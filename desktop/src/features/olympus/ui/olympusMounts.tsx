import { OlympusUsagePanel } from "@/features/agents/ui/OlympusUsagePanel";

export { OlympusProposalsPanel as OlympusProposalsTab } from "@/features/agents/ui/OlympusProposalsPanel";

export function OlympusUsageTab() {
  return <OlympusUsagePanel />;
}

export function OlympusAgentUsage(props: { workspace: string; agent: string }) {
  return <OlympusUsagePanel {...props} />;
}
