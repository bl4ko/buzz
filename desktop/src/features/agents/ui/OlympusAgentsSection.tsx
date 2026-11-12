import * as React from "react";

import {
  findOlympusAgent,
  type OlympusAgent,
  type OlympusWorkspaceGroup,
} from "@/features/agents/lib/olympusAgents";
import { useOlympusAgents } from "@/features/agents/useOlympusAgents";
import { Badge } from "@/shared/ui/badge";
import { SectionHeader } from "@/shared/ui/PageHeader";
import { Skeleton } from "@/shared/ui/skeleton";
import { OlympusAgentDetailsDialog } from "./OlympusAgentDetailsDialog";
import { formatOlympusTime, OlympusPhaseBadge } from "./OlympusAgentParts";

type SelectedAgent = { author: string; d: string };

export function OlympusAgentsSection({
  onOpenProfile,
}: {
  onOpenProfile: (pubkey: string) => void;
}) {
  const olympus = useOlympusAgents();
  const [selected, setSelected] = React.useState<SelectedAgent | null>(null);
  const selectedAgent = selected
    ? findOlympusAgent(olympus.groups, selected.author, selected.d)
    : null;
  const selectedGroup = selectedAgent
    ? (olympus.groups.find((group) =>
        group.agents.some((agent) => agent === selectedAgent),
      ) ?? null)
    : null;

  if (!olympus.isLoading && !olympus.error && olympus.groups.length === 0) {
    return null;
  }

  return (
    <section
      aria-label="Olympus agents"
      className="space-y-4"
      data-testid="olympus-agents-section"
    >
      <SectionHeader
        description="Agents that Hephaestus runs in the cluster, grouped by workspace."
        title="Olympus agents"
      />

      {olympus.isLoading ? (
        <div className="space-y-2" data-testid="olympus-agents-loading">
          <Skeleton className="h-14 w-full rounded-2xl" />
          <Skeleton className="h-14 w-full rounded-2xl" />
        </div>
      ) : null}

      {olympus.error ? (
        <p className="rounded-2xl border border-destructive/30 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          Couldn’t load Olympus agents. {olympus.error.message}
        </p>
      ) : null}

      {olympus.groups.map((group) => (
        <OlympusWorkspaceCard
          group={group}
          key={group.key}
          onSelectAgent={(agent) =>
            setSelected({ author: agent.author, d: agent.d })
          }
        />
      ))}

      {selectedAgent ? (
        <OlympusAgentDetailsDialog
          agent={selectedAgent}
          me={olympus.me}
          onOpenChange={(open) => {
            if (!open) setSelected(null);
          }}
          onOpenProfile={(pubkey) => {
            setSelected(null);
            onOpenProfile(pubkey);
          }}
          submitChange={olympus.submitChange}
          workspace={selectedGroup?.workspace ?? null}
        />
      ) : null}
    </section>
  );
}

function OlympusWorkspaceCard({
  group,
  onSelectAgent,
}: {
  group: OlympusWorkspaceGroup;
  onSelectAgent: (agent: OlympusAgent) => void;
}) {
  const workspace = group.workspace;
  const headingId = React.useId();
  return (
    <section
      aria-labelledby={headingId}
      className="overflow-hidden rounded-2xl border border-border/70 bg-card/40"
      data-testid={`olympus-workspace-${group.name}`}
    >
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border/60 bg-muted/20 px-4 py-3">
        <div className="flex min-w-0 flex-wrap items-center gap-2">
          <h3 className="truncate font-semibold text-foreground" id={headingId}>
            {group.name}
          </h3>
          {workspace ? (
            <OlympusPhaseBadge phase={workspace.phase} />
          ) : (
            <Badge variant="secondary">Unknown</Badge>
          )}
          {workspace?.reason ? (
            <span className="text-xs text-muted-foreground">
              {workspace.reason}
            </span>
          ) : null}
          {workspace?.managedBy === "gitops" ? (
            <Badge variant="outline">GitOps</Badge>
          ) : null}
        </div>
      </div>
      {group.agents.length === 0 ? (
        <p className="px-4 py-3 text-sm text-muted-foreground">
          No agents in this workspace.
        </p>
      ) : (
        <ul className="divide-y divide-border/50">
          {group.agents.map((agent) => (
            <li key={`${agent.author}:${agent.d}`}>
              <OlympusAgentRow agent={agent} onSelect={onSelectAgent} />
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function OlympusAgentRow({
  agent,
  onSelect,
}: {
  agent: OlympusAgent;
  onSelect: (agent: OlympusAgent) => void;
}) {
  const lastActivity = formatOlympusTime(agent.lastActivity);
  return (
    <button
      aria-haspopup="dialog"
      aria-label={`${agent.name}: ${agent.phase}, ${agent.spec.harness}, ${agent.spec.model}. Show details`}
      className="grid w-full gap-2 px-4 py-3 text-left transition-colors hover:bg-muted/30 focus-visible:bg-muted/30 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring lg:grid-cols-[minmax(0,1.5fr)_minmax(0,1fr)_minmax(0,0.7fr)_minmax(0,1.3fr)] lg:items-center lg:gap-4"
      data-testid={`olympus-agent-row-${agent.name}`}
      onClick={() => onSelect(agent)}
      type="button"
    >
      <span className="min-w-0">
        <span className="block truncate font-medium text-foreground">
          {agent.name}
        </span>
        <span className="block truncate text-xs text-muted-foreground">
          {agent.spec.harness} · {agent.spec.model}
        </span>
      </span>
      <span className="flex min-w-0 flex-wrap items-center gap-2">
        <OlympusPhaseBadge phase={agent.phase} />
        {agent.reason ? (
          <span className="truncate text-xs text-muted-foreground">
            {agent.reason}
          </span>
        ) : null}
      </span>
      <span className="text-xs text-muted-foreground">
        {lastActivity ? `Active ${lastActivity}` : "No activity"}
      </span>
      <span className="flex min-w-0 flex-wrap items-center gap-1.5 text-xs text-muted-foreground">
        {agent.spec.mcpServers.length > 0 ? (
          agent.spec.mcpServers.map((server) => (
            <Badge
              className="normal-case tracking-normal"
              key={server.name}
              variant="outline"
            >
              {server.name}
            </Badge>
          ))
        ) : (
          <span>No MCP servers</span>
        )}
        <span>
          · Memory {agent.spec.memory ? agent.spec.memory.bank : "off"}
        </span>
      </span>
    </button>
  );
}
