import * as React from "react";
import { Hash, Plug, Server } from "lucide-react";

import { useAppNavigation } from "@/app/navigation/useAppNavigation";
import {
  type OlympusAgent,
  type OlympusWorkspaceGroup,
  olympusEffectiveSpec,
} from "@/features/agents/lib/olympusAgents";
import { useOlympusAgents } from "@/features/agents/useOlympusAgents";
import { Button } from "@/shared/ui/button";
import { PubKey } from "@/shared/ui/PubKey";
import { OlympusConditions, OlympusHistoryList } from "./OlympusHistoryList";
import {
  OlympusCard,
  OlympusChip,
  OlympusEmptyState,
  OlympusFact,
  OlympusFacts,
  OlympusNone,
  OlympusPhase,
} from "./OlympusParts";

export function OlympusWorkspacesTab() {
  const olympus = useOlympusAgents();
  return (
    <div className="space-y-4" data-testid="olympus-workspaces">
      {olympus.groups.map((group) => (
        <OlympusWorkspaceCard group={group} key={group.key} />
      ))}
    </div>
  );
}

function OlympusWorkspaceCard({ group }: { group: OlympusWorkspaceGroup }) {
  const olympus = useOlympusAgents();
  const { goChannel } = useAppNavigation();
  const workspace = group.workspace;
  const history = olympus.history.filter(
    (entry) => entry.workspace === group.name,
  );
  return (
    <OlympusCard
      action={
        workspace?.channelId ? (
          <Button
            onClick={() => {
              if (workspace.channelId) void goChannel(workspace.channelId);
            }}
            size="sm"
            type="button"
            variant="outline"
          >
            <Hash />
            Open channel
          </Button>
        ) : null
      }
      testId={`olympus-workspace-card-${group.name}`}
      title={
        <>
          {group.name}
          {workspace ? <OlympusPhase phase={workspace.phase} /> : null}
        </>
      }
    >
      {workspace ? (
        <div className="space-y-5">
          <OlympusFacts>
            <OlympusFact label="Namespace">{workspace.namespace}</OlympusFact>
            <OlympusFact label="Agents">{group.agents.length}</OlympusFact>
            <OlympusFact label="Managed in">
              {workspace.managedBy === "gitops" ? "gitops-home" : "Olympus app"}
            </OlympusFact>
            <OlympusFact label="Quota">
              {workspace.quota ? (
                Object.entries(workspace.quota)
                  .map(([key, value]) => `${key} ${value}`)
                  .join(", ")
              ) : (
                <OlympusNone>No quota</OlympusNone>
              )}
            </OlympusFact>
            <OlympusFact label="Scheduler key">
              {workspace.schedulerPublicKey ? (
                <PubKey pubkey={workspace.schedulerPublicKey} />
              ) : (
                <OlympusNone>None</OlympusNone>
              )}
            </OlympusFact>
            <OlympusFact label="Templates">
              {workspace.templates.length > 0 ? (
                workspace.templates.map((template) => template.name).join(", ")
              ) : (
                <OlympusNone>None</OlympusNone>
              )}
            </OlympusFact>
          </OlympusFacts>
          <OlympusConditions conditions={workspace.conditions} />
          <div className="space-y-2">
            <h3 className="text-xs font-semibold text-muted-foreground">
              Recent changes
            </h3>
            <OlympusHistoryList entries={history.slice(0, 10)} />
          </div>
        </div>
      ) : (
        <OlympusNone>
          Hephaestus published agents, but no state for this workspace.
        </OlympusNone>
      )}
    </OlympusCard>
  );
}

type Usage = { workspaces: Set<string>; agents: OlympusAgent[] };

function useOlympusInventory() {
  const olympus = useOlympusAgents();
  return React.useMemo(() => {
    const providers = new Map<
      string,
      Usage & { models: Set<string>; protocols: Set<string> }
    >();
    const servers = new Map<string, Usage>();
    for (const group of olympus.groups) {
      for (const provider of group.workspace?.providers ?? []) {
        const entry = providers.get(provider.name) ?? {
          workspaces: new Set(),
          agents: [],
          models: new Set(),
          protocols: new Set(),
        };
        entry.workspaces.add(group.name);
        for (const model of provider.models) entry.models.add(model);
        for (const protocol of provider.protocols)
          entry.protocols.add(protocol);
        providers.set(provider.name, entry);
      }
      for (const name of group.workspace?.mcpServers ?? []) {
        const entry = servers.get(name) ?? {
          workspaces: new Set(),
          agents: [],
        };
        entry.workspaces.add(group.name);
        servers.set(name, entry);
      }
      for (const agent of group.agents) {
        const spec = olympusEffectiveSpec(agent);
        providers.get(spec.pool)?.agents.push(agent);
        for (const server of spec.mcpServers) {
          servers.get(server.name)?.agents.push(agent);
        }
        if (spec.memory) servers.get("hindsight")?.agents.push(agent);
      }
    }
    const sorted = <T,>(map: Map<string, T>) =>
      [...map.entries()].sort(([a], [b]) => a.localeCompare(b));
    return { providers: sorted(providers), servers: sorted(servers) };
  }, [olympus.groups]);
}

function AgentLinks({ agents }: { agents: OlympusAgent[] }) {
  const { goOlympusAgent } = useAppNavigation();
  if (agents.length === 0) return <OlympusNone>Not used</OlympusNone>;
  return (
    <span className="flex flex-wrap gap-1">
      {agents.map((agent) => (
        <button
          className="rounded-full bg-muted px-2 py-0.5 text-xs text-foreground hover:bg-muted/70"
          key={agent.d}
          onClick={() => void goOlympusAgent(agent.workspace, agent.name)}
          type="button"
        >
          {agent.workspace}/{agent.name}
        </button>
      ))}
    </span>
  );
}

export function OlympusProvidersTab() {
  const { providers, servers } = useOlympusInventory();
  if (providers.length === 0 && servers.length === 0) {
    return (
      <OlympusEmptyState icon={Server} title="No providers or MCP servers">
        <p>
          Workspaces publish the model providers and MCP servers they can use.
        </p>
      </OlympusEmptyState>
    );
  }
  return (
    <div className="space-y-4" data-testid="olympus-providers">
      <OlympusCard
        description="Model pools that agents can use, from the workspace or the shared olympus namespace."
        title="Model providers"
      >
        <ul className="divide-y divide-border/40">
          {providers.map(([name, entry]) => (
            <li
              className="grid gap-2 py-3 first:pt-0 last:pb-0 md:grid-cols-[12rem_minmax(0,1fr)]"
              data-testid={`olympus-provider-${name}`}
              key={name}
            >
              <span className="space-y-1">
                <span className="flex items-center gap-2 text-sm font-medium text-foreground">
                  <Server
                    aria-hidden
                    className="h-4 w-4 text-muted-foreground"
                  />
                  {name}
                </span>
                <span className="flex flex-wrap gap-1">
                  {[...entry.protocols].map((protocol) => (
                    <OlympusChip key={protocol}>{protocol}</OlympusChip>
                  ))}
                </span>
              </span>
              <span className="space-y-1.5 text-xs text-muted-foreground">
                <span className="block">
                  Models:{" "}
                  {entry.models.size > 0
                    ? [...entry.models].join(", ")
                    : "any model of the pool"}
                </span>
                <span className="block">
                  Workspaces: {[...entry.workspaces].join(", ")}
                </span>
                <AgentLinks agents={entry.agents} />
              </span>
            </li>
          ))}
        </ul>
      </OlympusCard>
      <OlympusCard
        description="MCP servers that agents can add. Hindsight is the memory server."
        title="MCP servers"
      >
        <ul className="divide-y divide-border/40">
          {servers.map(([name, entry]) => (
            <li
              className="grid gap-2 py-3 first:pt-0 last:pb-0 md:grid-cols-[12rem_minmax(0,1fr)]"
              data-testid={`olympus-mcp-${name}`}
              key={name}
            >
              <span className="flex items-center gap-2 text-sm font-medium text-foreground">
                <Plug aria-hidden className="h-4 w-4 text-muted-foreground" />
                {name}
              </span>
              <span className="space-y-1.5 text-xs text-muted-foreground">
                <span className="block">
                  Workspaces: {[...entry.workspaces].join(", ")}
                </span>
                <AgentLinks agents={entry.agents} />
              </span>
            </li>
          ))}
        </ul>
      </OlympusCard>
    </div>
  );
}
