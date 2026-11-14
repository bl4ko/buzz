import type * as React from "react";

import {
  type OlympusAgent,
  type OlympusWorkspace,
  olympusEffectiveSpec,
} from "@/features/agents/lib/olympusAgents";
import type { OlympusChange } from "@/features/agents/lib/olympusChangeRequests";
import {
  OlympusMcpControls,
  OlympusMemoryControls,
} from "@/features/agents/ui/OlympusAgentChangeControls";
import { CopyButton } from "@/features/agents/ui/CopyButton";
import { useOlympusAgents } from "@/features/agents/useOlympusAgents";
import { PubKey } from "@/shared/ui/PubKey";
import { olympusFieldLocked } from "../lib/olympusOwnership";
import { OlympusAgentUsage } from "./olympusMounts";
import { OlympusConditions, OlympusHistoryList } from "./OlympusHistoryList";
import {
  formatOlympusAgo,
  OlympusCard,
  OlympusChip,
  OlympusFact,
  OlympusFacts,
  OlympusGitLock,
  OlympusNone,
} from "./OlympusParts";
import { OlympusSchedulesTab } from "./OlympusSchedulesTab";

type Send = (change: OlympusChange) => unknown;

function none(text = "None") {
  return <OlympusNone>{text}</OlympusNone>;
}

function list(items: readonly React.ReactNode[], empty: string) {
  if (items.length === 0) return none(empty);
  return (
    <ul className="space-y-1">
      {items.map((item, index) => (
        // biome-ignore lint/suspicious/noArrayIndexKey: static rendered list
        <li key={index}>{item}</li>
      ))}
    </ul>
  );
}

function resources(value: Record<string, Record<string, string>> | null) {
  if (!value) return none("Operator default");
  return Object.entries(value)
    .map(
      ([kind, map]) =>
        `${kind}: ${Object.entries(map)
          .map(([key, amount]) => `${key} ${amount}`)
          .join(", ")}`,
    )
    .join(" · ");
}

export function OlympusAgentSections({
  agent,
  pending,
  send,
  workspace,
}: {
  agent: OlympusAgent;
  pending: boolean;
  send: Send;
  workspace: OlympusWorkspace | null;
}) {
  const olympus = useOlympusAgents();
  const spec = olympusEffectiveSpec(agent);
  const locked = (field: string) => olympusFieldLocked(agent, `spec.${field}`);
  const fromTemplate = (field: keyof typeof agent.spec) =>
    agent.spec.template !== null &&
    (agent.spec[field] === null || agent.spec[field] === "") &&
    spec[field] !== null &&
    spec[field] !== "";
  const tag = (field: keyof typeof agent.spec, value: React.ReactNode) =>
    fromTemplate(field) ? (
      <>
        {value}{" "}
        <span className="text-xs text-muted-foreground">(template)</span>
      </>
    ) : (
      value
    );
  const history = olympus.history.filter(
    (entry) =>
      entry.workspace === agent.workspace && entry.agent === agent.name,
  );

  return (
    <div className="space-y-4">
      <OlympusCard title="Overview">
        <OlympusFacts>
          <OlympusFact label="Last activity">
            {formatOlympusAgo(agent.lastActivity) ?? none("No activity")}
          </OlympusFact>
          <OlympusFact label="Managed in">
            {agent.managedBy === "gitops" ? "gitops-home" : "Olympus app"}
          </OlympusFact>
          <OlympusFact label="Template">
            {agent.spec.template ?? none()}
            {agent.runtime.template?.namespace
              ? ` (${agent.runtime.template.namespace})`
              : ""}
          </OlympusFact>
          <OlympusFact label="Owner" locked={locked("owner")}>
            {agent.owner ? (
              <PubKey pubkey={agent.owner} />
            ) : (
              none("Default owner")
            )}
          </OlympusFact>
          <OlympusFact label="Public key">
            {agent.publicKey ? (
              <span className="flex items-center gap-1">
                <PubKey pubkey={agent.publicKey} />
                <CopyButton
                  iconOnly
                  label="Copy agent public key"
                  size="icon-xs"
                  value={agent.publicKey}
                  variant="ghost"
                />
              </span>
            ) : (
              none("Not enrolled")
            )}
          </OlympusFact>
          <OlympusFact label="Identity path" locked={locked("identityPath")}>
            {agent.spec.identityPath ?? none("Default")}
          </OlympusFact>
        </OlympusFacts>
        <div className="mt-4">
          <OlympusConditions conditions={agent.conditions} />
        </div>
      </OlympusCard>

      <OlympusCard title="Runtime">
        <OlympusFacts>
          <OlympusFact label="Harness" locked={locked("harness")}>
            {tag("harness", spec.harness)}
          </OlympusFact>
          <OlympusFact label="Pool" locked={locked("pool")}>
            {tag("pool", spec.pool)}
          </OlympusFact>
          <OlympusFact label="Model" locked={locked("model")}>
            {tag("model", spec.model)}
          </OlympusFact>
          <OlympusFact label="Effort" locked={locked("effort")}>
            {spec.effort ? tag("effort", spec.effort) : none("Default")}
          </OlympusFact>
          <OlympusFact label="Image" locked={locked("image")}>
            {spec.image ? (
              <span className="break-all font-mono text-xs">{spec.image}</span>
            ) : (
              none("Operator default")
            )}
          </OlympusFact>
          <OlympusFact label="Resources" locked={locked("resources")}>
            {resources(spec.resources)}
          </OlympusFact>
          <OlympusFact label="Storage" locked={locked("storage")}>
            {spec.storage ?? none("Default")}
          </OlympusFact>
          <OlympusFact label="Runtime class" locked={locked("runtimeClass")}>
            {spec.runtimeClass ?? none("Default")}
          </OlympusFact>
          <OlympusFact label="Backup" locked={locked("backup")}>
            {spec.backup ? "On" : "Off"}
            {agent.runtime.backup ? " · active" : ""}
          </OlympusFact>
        </OlympusFacts>
      </OlympusCard>

      <OlympusCard title="Access">
        <div className="space-y-5">
          <div className="space-y-2">
            <h3 className="flex items-center gap-1.5 text-xs font-semibold text-muted-foreground">
              MCP servers
              {locked("mcpServers") ? (
                <OlympusGitLock field="MCP servers" />
              ) : null}
            </h3>
            {locked("mcpServers") ? (
              list(
                spec.mcpServers.map((server) => (
                  <span className="text-sm" key={server.name}>
                    <span className="font-medium">{server.name}</span>
                    <span className="text-muted-foreground">
                      {" "}
                      {server.tools ? server.tools.join(", ") : "all tools"}
                    </span>
                  </span>
                )),
                "No MCP servers",
              )
            ) : (
              <OlympusMcpControls
                agent={agent}
                disabled={pending}
                send={send}
                workspace={workspace}
              />
            )}
          </div>
          <OlympusFacts>
            <OlympusFact label="Services" locked={locked("services")}>
              {list(spec.services, "No services")}
            </OlympusFact>
            <OlympusFact label="Secrets" locked={locked("secrets")}>
              {list(
                spec.secrets.map((secret) =>
                  secret.env ? `${secret.name} → ${secret.env}` : secret.name,
                ),
                "No secrets",
              )}
            </OlympusFact>
            <OlympusFact
              label="Kubernetes role"
              locked={locked("kubernetesRole")}
            >
              {spec.kubernetesRole ?? none()}
              {agent.runtime.kubernetesRole &&
              agent.runtime.kubernetesRole !== spec.kubernetesRole
                ? ` (bound: ${agent.runtime.kubernetesRole})`
                : ""}
            </OlympusFact>
            <OlympusFact label="Egress" locked={locked("egress")}>
              <span className="mb-1 flex flex-wrap gap-1">
                <OlympusChip>
                  Mode {agent.runtime.egressMode ?? "unknown"}
                </OlympusChip>
                {agent.runtime.egressProxy ? (
                  <OlympusChip>Proxy</OlympusChip>
                ) : null}
              </span>
              {list(
                spec.egress.map((rule) => {
                  const target =
                    rule.host ?? rule.cidr ?? rule.preset ?? "unknown target";
                  return rule.ports.length > 0
                    ? `${target} on ports ${rule.ports.join(", ")}`
                    : target;
                }),
                "No egress rules",
              )}
            </OlympusFact>
            <OlympusFact label="Responds to" locked={locked("respondTo")}>
              {list(
                spec.respondTo.map((key) => <PubKey key={key} pubkey={key} />),
                "Owner and scheduler only",
              )}
            </OlympusFact>
          </OlympusFacts>
        </div>
      </OlympusCard>

      <OlympusCard title="Knowledge">
        <div className="space-y-5">
          <div className="space-y-2">
            <h3 className="flex items-center gap-1.5 text-xs font-semibold text-muted-foreground">
              Instructions
              {locked("instructions") || locked("instructionsFrom") ? (
                <OlympusGitLock field="Instructions" />
              ) : null}
            </h3>
            {agent.instructionsFile ? (
              <p
                className="text-sm"
                data-testid="olympus-agent-instructions-file"
              >
                File in Olympus git{" "}
                <span className="font-mono">
                  {agent.instructionsFile.repo}/{agent.instructionsFile.path}
                </span>
              </p>
            ) : spec.instructionsFrom ? (
              <p className="text-sm">
                From skills repository{" "}
                <span className="font-mono">
                  {spec.instructionsFrom.skillsRepo}/
                  {spec.instructionsFrom.path}
                </span>
              </p>
            ) : spec.instructions ? (
              <pre
                className="max-h-72 overflow-auto whitespace-pre-wrap break-words rounded-lg border border-border/60 bg-muted/30 p-3 font-mono text-xs text-foreground"
                data-testid="olympus-agent-instructions"
              >
                {spec.instructions}
              </pre>
            ) : (
              none("No instructions")
            )}
            {agent.instructionsTruncated ? (
              <p className="text-xs text-muted-foreground">
                Shortened. The full text is in the cluster object.
              </p>
            ) : null}
          </div>
          <OlympusFacts>
            <OlympusFact label="Memory" locked={locked("memory")}>
              {locked("memory") ? (
                spec.memory ? (
                  `Bank ${spec.memory.bank}`
                ) : (
                  "Off"
                )
              ) : (
                <OlympusMemoryControls
                  agent={agent}
                  disabled={pending}
                  send={send}
                />
              )}
            </OlympusFact>
            <OlympusFact label="Skills" locked={locked("skills")}>
              {list(
                spec.skills.map((skill) => `${skill.repo}/${skill.name}`),
                "No skills",
              )}
            </OlympusFact>
            <OlympusFact label="Git sources" locked={locked("gitSources")}>
              {list(
                spec.gitSources.map(
                  (source) => `${source.name} (${source.access})`,
                ),
                "No git sources",
              )}
            </OlympusFact>
          </OlympusFacts>
        </div>
      </OlympusCard>

      <OlympusCard title="Schedules">
        <OlympusSchedulesTab agent={agent.d} />
      </OlympusCard>

      <OlympusAgentUsage agent={agent.name} workspace={agent.workspace} />

      <OlympusCard
        description="Change requests from this app and their results."
        title="Change history"
      >
        <OlympusHistoryList
          entries={history.slice(0, 20)}
          testId="olympus-agent-history"
        />
      </OlympusCard>
    </div>
  );
}
