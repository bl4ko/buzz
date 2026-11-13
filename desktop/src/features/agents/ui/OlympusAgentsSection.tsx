import * as React from "react";

import {
  findOlympusAgent,
  type OlympusAgent,
  type OlympusWorkspaceGroup,
} from "@/features/agents/lib/olympusAgents";
import {
  olympusRequestKey,
  useOlympusRequestState,
} from "@/features/agents/lib/olympusChangeRequests";
import {
  type OlympusAgentsState,
  useOlympusAgents,
} from "@/features/agents/useOlympusAgents";
import { Pause, Play, Plus } from "lucide-react";
import { Badge } from "@/shared/ui/badge";
import { Button } from "@/shared/ui/button";
import { SectionHeader } from "@/shared/ui/PageHeader";
import { Skeleton } from "@/shared/ui/skeleton";
import { OlympusAgentDetailsDialog } from "./OlympusAgentDetailsDialog";
import {
  formatOlympusTime,
  OlympusPhaseBadge,
  OlympusRequestStatus,
} from "./OlympusAgentParts";
import { OlympusNewAgentDialog } from "./OlympusNewAgentDialog";
import {
  OlympusProposalCard,
  useVisibleOlympusProposals,
} from "./OlympusProposalCard";
import { olympusProposalKey } from "@/features/agents/lib/olympusProposals";

type SelectedAgent = { author: string; d: string };

export function OlympusAgentsSection({
  onOpenProfile,
}: {
  onOpenProfile: (pubkey: string) => void;
}) {
  const olympus = useOlympusAgents();
  const proposals = useVisibleOlympusProposals(olympus.proposals);
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

      {proposals.length > 0 ? (
        <section
          aria-label="Change proposals"
          className="space-y-2"
          data-testid="olympus-proposals"
        >
          <h3 className="text-sm font-semibold text-foreground">
            Change proposals
          </h3>
          {proposals.map((proposal) => (
            <OlympusProposalCard
              key={olympusProposalKey(proposal)}
              proposal={proposal}
              submitChange={olympus.submitChange}
            />
          ))}
        </section>
      ) : null}

      {olympus.groups.map((group) => (
        <OlympusWorkspaceCard
          group={group}
          key={group.key}
          submitChange={olympus.submitChange}
          onSelectAgent={(agent) =>
            setSelected({ author: agent.author, d: agent.d })
          }
        />
      ))}

      {selectedAgent ? (
        <OlympusAgentDetailsDialog
          agent={selectedAgent}
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
  submitChange,
}: {
  group: OlympusWorkspaceGroup;
  onSelectAgent: (agent: OlympusAgent) => void;
  submitChange: OlympusAgentsState["submitChange"];
}) {
  const workspace = group.workspace;
  const headingId = React.useId();
  const [isCreating, setIsCreating] = React.useState(false);
  const workspaceKey = olympusRequestKey(group.name, null);
  const createKey = `${workspaceKey}#create`;
  const workspaceRequest = useOlympusRequestState(workspaceKey);
  const createRequest = useOlympusRequestState(createKey);
  const editable = workspace !== null && workspace.managedBy !== "gitops";
  const target = { operator: group.author, workspace: group.name };
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
        {editable ? (
          <div className="flex flex-wrap items-center gap-2">
            <Button
              aria-label={`${workspace.suspend ? "Resume" : "Suspend"} workspace ${group.name}`}
              disabled={workspaceRequest?.phase === "pending"}
              onClick={() => {
                void submitChange(
                  workspaceKey,
                  { ...target, agent: null },
                  { action: workspace.suspend ? "resume" : "suspend" },
                );
              }}
              size="sm"
              type="button"
              variant="outline"
            >
              {workspace.suspend ? <Play /> : <Pause />}
              {workspace.suspend ? "Resume workspace" : "Suspend workspace"}
            </Button>
            <Button
              aria-label={`New agent in ${group.name}`}
              disabled={createRequest?.phase === "pending"}
              onClick={() => setIsCreating(true)}
              size="sm"
              type="button"
              variant="outline"
            >
              <Plus />
              New agent
            </Button>
          </div>
        ) : null}
      </div>
      {workspaceRequest || createRequest ? (
        <div className="space-y-2 border-b border-border/60 px-4 py-3">
          <OlympusRequestStatus
            state={workspaceRequest}
            testId={`olympus-workspace-request-${group.name}`}
          />
          <OlympusRequestStatus
            state={createRequest}
            testId={`olympus-create-request-${group.name}`}
          />
        </div>
      ) : null}
      {isCreating && workspace ? (
        <OlympusNewAgentDialog
          existingNames={group.agents.map((agent) => agent.name)}
          onCreate={(name, change) => {
            setIsCreating(false);
            void submitChange(createKey, { ...target, agent: name }, change);
          }}
          onOpenChange={setIsCreating}
          workspace={workspace}
        />
      ) : null}
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
        <span>Memory {agent.spec.memory ? agent.spec.memory.bank : "off"}</span>
      </span>
    </button>
  );
}
