import * as React from "react";
import {
  AlertTriangle,
  ChevronRight,
  Hash,
  Pause,
  Play,
  Plus,
  Users,
} from "lucide-react";

import { useAppNavigation } from "@/app/navigation/useAppNavigation";
import {
  type OlympusAgent,
  type OlympusWorkspaceGroup,
  olympusAgentLabel,
  olympusEffectiveSpec,
} from "@/features/agents/lib/olympusAgents";
import {
  olympusRequestKey,
  useOlympusRequestState,
} from "@/features/agents/lib/olympusChangeRequests";
import { OlympusRequestStatus } from "@/features/agents/ui/OlympusAgentParts";
import { useOlympusAgents } from "@/features/agents/useOlympusAgents";
import { Button } from "@/shared/ui/button";
import { olympusFieldLocked } from "../lib/olympusOwnership";
import { OlympusNewAgentDialog } from "./OlympusNewAgentDialog";
import {
  formatOlympusAgo,
  OlympusAgentAvatar,
  OlympusChip,
  OlympusEmptyState,
  OlympusGitLock,
  OlympusMasterChip,
  OlympusPhase,
} from "./OlympusParts";

export function OlympusAgentsTab() {
  const olympus = useOlympusAgents();
  return (
    <div className="space-y-5" data-testid="olympus-agents-tab">
      {olympus.groups.map((group) => (
        <OlympusWorkspaceAgents group={group} key={group.key} />
      ))}
    </div>
  );
}

function OlympusWorkspaceAgents({ group }: { group: OlympusWorkspaceGroup }) {
  const olympus = useOlympusAgents();
  const { goChannel } = useAppNavigation();
  const workspace = group.workspace;
  const headingId = React.useId();
  const [creating, setCreating] = React.useState(false);
  const workspaceKey = olympusRequestKey(group.name, null);
  const createKey = `${workspaceKey}#create`;
  const workspaceRequest = useOlympusRequestState(workspaceKey);
  const createRequest = useOlympusRequestState(createKey);
  const suspendLocked = workspace
    ? olympusFieldLocked(workspace, "spec.suspend")
    : true;
  const target = { operator: group.author, workspace: group.name };

  return (
    <section
      aria-labelledby={headingId}
      className="overflow-hidden rounded-xl border border-border/70 bg-card/60"
      data-testid={`olympus-workspace-${group.name}`}
    >
      <header className="flex flex-wrap items-center justify-between gap-3 border-b border-border/60 px-4 py-2.5">
        <div className="flex min-w-0 flex-wrap items-center gap-2">
          <h2
            className="truncate text-sm font-semibold text-foreground"
            id={headingId}
          >
            {group.name}
          </h2>
          {workspace ? (
            <OlympusPhase phase={workspace.phase} />
          ) : (
            <OlympusChip>No workspace state</OlympusChip>
          )}
          <span className="text-xs text-muted-foreground">
            {group.agents.length}{" "}
            {group.agents.length === 1 ? "agent" : "agents"}
          </span>
          {workspace?.reason && workspace.phase !== "Ready" ? (
            <span className="text-xs text-muted-foreground">
              {workspace.reason}
            </span>
          ) : null}
        </div>
        <div className="flex flex-wrap items-center gap-1.5">
          {workspace?.channelId ? (
            <Button
              onClick={() => {
                if (workspace.channelId) void goChannel(workspace.channelId);
              }}
              size="sm"
              type="button"
              variant="ghost"
            >
              <Hash />
              Channel
            </Button>
          ) : null}
          {workspace ? (
            suspendLocked ? (
              <span className="flex items-center gap-1 px-2 text-xs text-muted-foreground">
                <OlympusGitLock field="Workspace suspend" />
                {workspace.suspend ? "Suspended in git" : "Suspend in git"}
              </span>
            ) : (
              <Button
                aria-label={`${workspace.suspend ? "Resume" : "Suspend"} workspace ${group.name}`}
                disabled={workspaceRequest?.phase === "pending"}
                onClick={() => {
                  void olympus.submitChange(
                    workspaceKey,
                    { ...target, agent: null },
                    { action: workspace.suspend ? "resume" : "suspend" },
                  );
                }}
                size="sm"
                type="button"
                variant="ghost"
              >
                {workspace.suspend ? <Play /> : <Pause />}
                {workspace.suspend ? "Resume" : "Suspend"}
              </Button>
            )
          ) : null}
          {workspace ? (
            <Button
              aria-label={`New agent in ${group.name}`}
              disabled={createRequest?.phase === "pending"}
              onClick={() => setCreating(true)}
              size="sm"
              type="button"
              variant="outline"
            >
              <Plus />
              New agent
            </Button>
          ) : null}
        </div>
      </header>
      {workspaceRequest || createRequest ? (
        <div className="space-y-2 border-b border-border/60 px-4 py-2.5">
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
      {creating && workspace ? (
        <OlympusNewAgentDialog
          group={group}
          onOpenChange={setCreating}
          requestKey={createKey}
        />
      ) : null}
      {group.agents.length === 0 ? (
        <div className="px-4 py-6">
          <OlympusEmptyState icon={Users} title="No agents in this workspace">
            <p>
              Select New agent to create one from a template or a blank form.
            </p>
          </OlympusEmptyState>
        </div>
      ) : (
        <ul className="divide-y divide-border/50">
          {group.agents.map((agent) => (
            <li key={`${agent.author}:${agent.d}`}>
              <OlympusAgentRow agent={agent} />
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function OlympusAgentRow({ agent }: { agent: OlympusAgent }) {
  const { goOlympusAgent } = useAppNavigation();
  const spec = olympusEffectiveSpec(agent);
  const failed = agent.schedules.filter(
    (schedule) => schedule.lastResult === "Failed",
  ).length;
  const lastActivity = formatOlympusAgo(agent.lastActivity);
  const label = olympusAgentLabel(agent);
  const parts = [
    label,
    agent.phase,
    `${spec.harness}, ${spec.model}`,
    `${agent.schedules.length} ${agent.schedules.length === 1 ? "schedule" : "schedules"}`,
  ];
  if (failed > 0) parts.push(`${failed} failed`);
  return (
    <button
      aria-label={`${parts.join(", ")}. Open agent`}
      className="grid w-full grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-3 px-4 py-2.5 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring"
      data-testid={`olympus-agent-row-${agent.name}`}
      onClick={() => void goOlympusAgent(agent.workspace, agent.name)}
      type="button"
    >
      <OlympusAgentAvatar agent={agent} />
      <span className="grid min-w-0 gap-1 md:grid-cols-[minmax(0,1.3fr)_minmax(0,1fr)_auto] md:items-center md:gap-4">
        <span className="min-w-0">
          <span className="flex min-w-0 items-center gap-2">
            <span className="truncate text-sm font-medium text-foreground">
              {label}
            </span>
            {label !== agent.name ? (
              <span className="truncate font-mono text-xs text-muted-foreground">
                {agent.name}
              </span>
            ) : null}
            {agent.role === "master" ? <OlympusMasterChip /> : null}
          </span>
          <span className="block truncate text-xs text-muted-foreground">
            {spec.harness} · {spec.model}
            {spec.effort ? ` · ${spec.effort}` : ""}
          </span>
        </span>
        <span className="flex min-w-0 flex-wrap items-center gap-1.5">
          <OlympusPhase phase={agent.phase} />
          {failed > 0 ? (
            <OlympusChip icon={AlertTriangle} tone="bad">
              {failed} failed
            </OlympusChip>
          ) : null}
        </span>
        <span className="text-xs text-muted-foreground md:text-right">
          {lastActivity ? `Active ${lastActivity}` : "No activity"}
        </span>
      </span>
      <ChevronRight
        aria-hidden
        className="h-4 w-4 shrink-0 text-muted-foreground"
      />
    </button>
  );
}
