import * as React from "react";
import { MessageSquare, UserRound } from "lucide-react";

import { useAppNavigation } from "@/app/navigation/useAppNavigation";
import type {
  OlympusAgent,
  OlympusWorkspace,
} from "@/features/agents/lib/olympusAgents";
import {
  type OlympusChange,
  olympusRequestKey,
  useOlympusRequestState,
} from "@/features/agents/lib/olympusChangeRequests";
import type { OlympusAgentsState } from "@/features/agents/useOlympusAgents";
import { useOpenDmMutation } from "@/features/channels/hooks";
import { Button } from "@/shared/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/shared/ui/dialog";
import { PubKey } from "@/shared/ui/PubKey";
import { CopyButton } from "./CopyButton";
import {
  OlympusAgentActions,
  OlympusAgentEditForm,
  OlympusMcpControls,
  OlympusMemoryControls,
} from "./OlympusAgentChangeControls";
import {
  formatOlympusTime,
  OlympusDetailSection,
  OlympusEmptyValue,
  OlympusPhaseBadge,
  OlympusRequestStatus,
} from "./OlympusAgentParts";

export function OlympusAgentDetailsDialog({
  agent,
  onOpenChange,
  onOpenProfile,
  submitChange,
  workspace,
}: {
  agent: OlympusAgent;
  onOpenChange: (open: boolean) => void;
  onOpenProfile: (pubkey: string) => void;
  submitChange: OlympusAgentsState["submitChange"];
  workspace: OlympusWorkspace | null;
}) {
  const openDmMutation = useOpenDmMutation();
  const { goChannel } = useAppNavigation();
  const publicKey = agent.publicKey;
  const requestKey = olympusRequestKey(agent.workspace, agent.name);
  const request = useOlympusRequestState(requestKey);
  const pending = request?.phase === "pending";
  const editable = agent.managedBy !== "gitops";
  const [isEditing, setIsEditing] = React.useState(false);
  const send = (change: OlympusChange) => {
    void submitChange(
      requestKey,
      { operator: agent.author, workspace: agent.workspace, agent: agent.name },
      change,
    );
  };

  async function openDm() {
    if (!publicKey) return;
    const dm = await openDmMutation.mutateAsync({ pubkeys: [publicKey] });
    onOpenChange(false);
    await goChannel(dm.id);
  }

  return (
    <Dialog onOpenChange={onOpenChange} open>
      <DialogContent
        className="max-w-3xl overflow-hidden p-0"
        data-testid="olympus-agent-details"
      >
        <div className="flex max-h-[85vh] flex-col">
          <DialogHeader className="shrink-0 border-b border-border/60 px-6 py-5 pr-14">
            <div className="flex flex-wrap items-center gap-2">
              <DialogTitle>{agent.name}</DialogTitle>
              <OlympusPhaseBadge phase={agent.phase} />
            </div>
            <DialogDescription>
              {agent.spec.harness} agent in workspace {agent.workspace}
              {agent.reason ? `. ${agent.reason}` : ""}
            </DialogDescription>
          </DialogHeader>

          <div className="min-h-0 flex-1 space-y-6 overflow-y-auto px-6 py-5">
            <div className="flex flex-wrap items-center gap-2">
              <Button
                disabled={!publicKey || openDmMutation.isPending}
                onClick={() => {
                  void openDm();
                }}
                size="sm"
                type="button"
                variant="outline"
              >
                <MessageSquare />
                Message
              </Button>
              <Button
                disabled={!publicKey}
                onClick={() => {
                  if (publicKey) onOpenProfile(publicKey);
                }}
                size="sm"
                type="button"
                variant="outline"
              >
                <UserRound />
                Profile
              </Button>
              {editable ? (
                <OlympusAgentActions
                  agent={agent}
                  disabled={pending}
                  isEditing={isEditing}
                  onEdit={() => setIsEditing((value) => !value)}
                  send={send}
                />
              ) : (
                <span className="text-xs text-muted-foreground">
                  Managed by GitOps. Change it in the repository.
                </span>
              )}
            </div>
            <OlympusRequestStatus
              state={request}
              testId="olympus-agent-request-status"
            />
            {editable && isEditing ? (
              <OlympusAgentEditForm
                agent={agent}
                disabled={pending}
                onCancel={() => setIsEditing(false)}
                send={send}
                workspace={workspace}
              />
            ) : null}
            {openDmMutation.error instanceof Error ? (
              <p className="text-xs text-destructive">
                {openDmMutation.error.message}
              </p>
            ) : null}

            <OlympusAgentConfiguration agent={agent} />
            <OlympusAgentLists
              agent={agent}
              controls={
                editable
                  ? {
                      mcp: (
                        <OlympusMcpControls
                          agent={agent}
                          disabled={pending}
                          send={send}
                          workspace={workspace}
                        />
                      ),
                      memory: (
                        <OlympusMemoryControls
                          agent={agent}
                          disabled={pending}
                          send={send}
                        />
                      ),
                    }
                  : null
              }
            />
            <OlympusAgentSchedules agent={agent} />
            <OlympusAgentConditions agent={agent} />
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}

function Field({
  children,
  label,
}: {
  children: React.ReactNode;
  label: string;
}) {
  return (
    <div className="min-w-0 space-y-0.5">
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className="min-w-0 break-words text-sm text-foreground">
        {children}
      </dd>
    </div>
  );
}

function OlympusAgentConfiguration({ agent }: { agent: OlympusAgent }) {
  return (
    <>
      <OlympusDetailSection title="Configuration">
        <dl className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <Field label="Workspace">{agent.workspace}</Field>
          <Field label="Namespace">{agent.namespace || "None"}</Field>
          <Field label="Harness">{agent.spec.harness}</Field>
          <Field label="Pool">{agent.spec.pool}</Field>
          <Field label="Model">{agent.spec.model}</Field>
          <Field label="Effort">{agent.spec.effort ?? "Default"}</Field>
          <Field label="Owner">
            {agent.owner ? (
              <PubKey pubkey={agent.owner} variant="full" />
            ) : (
              "Hephaestus default owner"
            )}
          </Field>
          <Field label="Managed by">
            {agent.managedBy === "gitops" ? "GitOps" : "Olympus app"}
          </Field>
          <Field label="Last activity">
            {formatOlympusTime(agent.lastActivity) ?? "None"}
          </Field>
        </dl>
        <div className="space-y-1">
          <p className="text-xs text-muted-foreground">Public key</p>
          {agent.publicKey ? (
            <div className="flex flex-wrap items-center gap-2">
              <span
                className="break-all font-mono text-xs text-foreground"
                data-testid="olympus-agent-public-key"
              >
                {agent.publicKey}
              </span>
              <CopyButton
                iconOnly
                label="Copy agent public key"
                size="icon-xs"
                value={agent.publicKey}
                variant="ghost"
              />
            </div>
          ) : (
            <OlympusEmptyValue>Not enrolled yet.</OlympusEmptyValue>
          )}
        </div>
      </OlympusDetailSection>

      <OlympusDetailSection title="Instructions">
        {agent.spec.instructions ? (
          <pre
            className="max-h-64 overflow-auto whitespace-pre-wrap break-words rounded-lg border border-border/60 bg-muted/30 p-3 font-mono text-xs text-foreground"
            data-testid="olympus-agent-instructions"
          >
            {agent.spec.instructions}
          </pre>
        ) : (
          <OlympusEmptyValue>No instructions.</OlympusEmptyValue>
        )}
      </OlympusDetailSection>
    </>
  );
}

function ItemList({ empty, items }: { empty: string; items: string[] }) {
  return items.length > 0 ? (
    <ul className="space-y-1 text-sm text-foreground">
      {items.map((item) => (
        <li className="break-words" key={item}>
          {item}
        </li>
      ))}
    </ul>
  ) : (
    <OlympusEmptyValue>{empty}</OlympusEmptyValue>
  );
}

function OlympusAgentLists({
  agent,
  controls,
}: {
  agent: OlympusAgent;
  controls: { mcp: React.ReactNode; memory: React.ReactNode } | null;
}) {
  const { spec } = agent;
  return (
    <>
      <OlympusDetailSection title="MCP servers">
        {controls ? (
          controls.mcp
        ) : (
          <ItemList
            empty="No MCP servers."
            items={spec.mcpServers.map((server) =>
              server.tools
                ? `${server.name}: ${server.tools.join(", ")}`
                : `${server.name}: all tools`,
            )}
          />
        )}
      </OlympusDetailSection>
      <OlympusDetailSection title="Memory">
        {controls ? (
          controls.memory
        ) : (
          <OlympusEmptyValue>
            {spec.memory
              ? `Memory bank: ${spec.memory.bank}.`
              : "Memory is off for this agent."}
          </OlympusEmptyValue>
        )}
      </OlympusDetailSection>
      <div className="grid gap-6 sm:grid-cols-2">
        <OlympusDetailSection title="Services">
          <ItemList empty="No services." items={spec.services} />
        </OlympusDetailSection>
        <OlympusDetailSection title="Git sources">
          <ItemList
            empty="No git sources."
            items={spec.gitSources.map(
              (source) => `${source.name} (${source.access})`,
            )}
          />
        </OlympusDetailSection>
        <OlympusDetailSection title="Skills">
          <ItemList
            empty="No skills."
            items={spec.skills.map((skill) => `${skill.repo}/${skill.name}`)}
          />
        </OlympusDetailSection>
        <OlympusDetailSection title="Egress">
          <ItemList
            empty="No egress rules."
            items={spec.egress.map((rule) => {
              const target =
                rule.host ?? rule.cidr ?? rule.preset ?? "unknown target";
              return rule.ports.length > 0
                ? `${target} on ports ${rule.ports.join(", ")}`
                : target;
            })}
          />
        </OlympusDetailSection>
      </div>
    </>
  );
}

const TABLE_CLASS = "w-full min-w-[32rem] text-left text-xs";
const HEAD_CLASS = "border-b border-border/60 text-muted-foreground";
const CELL_CLASS = "px-2 py-1.5 align-top";

function firstLine(value: string) {
  const line = value.split("\n")[0] ?? "";
  return line.length > 80 ? `${line.slice(0, 79)}…` : line;
}

function OlympusAgentSchedules({ agent }: { agent: OlympusAgent }) {
  return (
    <OlympusDetailSection title="Schedules">
      {agent.schedules.length === 0 ? (
        <OlympusEmptyValue>No schedules.</OlympusEmptyValue>
      ) : (
        <div className="overflow-x-auto">
          <table className={TABLE_CLASS}>
            <thead className={HEAD_CLASS}>
              <tr>
                <th className={CELL_CLASS} scope="col">
                  Name
                </th>
                <th className={CELL_CLASS} scope="col">
                  Cron
                </th>
                <th className={CELL_CLASS} scope="col">
                  Work
                </th>
                <th className={CELL_CLASS} scope="col">
                  Last run
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border/40 text-foreground">
              {agent.schedules.map((schedule) => (
                <tr key={schedule.name}>
                  <td className={CELL_CLASS}>
                    {schedule.name}
                    {schedule.suspend ? " (suspended)" : ""}
                  </td>
                  <td className={`${CELL_CLASS} font-mono`}>
                    {schedule.cron ?? "None"}
                    {schedule.timeZone ? (
                      <span className="block font-sans text-muted-foreground">
                        {schedule.timeZone}
                      </span>
                    ) : null}
                  </td>
                  <td className={CELL_CLASS}>
                    {schedule.prompt ? (
                      <span className="block">
                        Prompt: {firstLine(schedule.prompt)}
                      </span>
                    ) : null}
                    {schedule.script ? (
                      <span className="block">
                        Script: {firstLine(schedule.script)}
                      </span>
                    ) : null}
                    {schedule.workspace ? (
                      <span className="block text-muted-foreground">
                        Posts to the workspace channel
                      </span>
                    ) : null}
                  </td>
                  <td className={CELL_CLASS}>
                    {formatOlympusTime(schedule.lastRunTime) ?? "Never"}
                    {schedule.lastResult ? (
                      <span className="block text-muted-foreground">
                        {schedule.lastResult}
                      </span>
                    ) : null}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </OlympusDetailSection>
  );
}

function OlympusAgentConditions({ agent }: { agent: OlympusAgent }) {
  return (
    <OlympusDetailSection title="Conditions">
      {agent.conditions.length === 0 ? (
        <OlympusEmptyValue>No conditions.</OlympusEmptyValue>
      ) : (
        <div className="overflow-x-auto">
          <table className={TABLE_CLASS}>
            <thead className={HEAD_CLASS}>
              <tr>
                {["Type", "Status", "Reason", "Message", "Changed"].map(
                  (label) => (
                    <th className={CELL_CLASS} key={label} scope="col">
                      {label}
                    </th>
                  ),
                )}
              </tr>
            </thead>
            <tbody className="divide-y divide-border/40 text-foreground">
              {agent.conditions.map((condition) => (
                <tr key={condition.type}>
                  <td className={CELL_CLASS}>{condition.type}</td>
                  <td className={CELL_CLASS}>{condition.status}</td>
                  <td className={CELL_CLASS}>{condition.reason ?? ""}</td>
                  <td className={`${CELL_CLASS} break-words`}>
                    {condition.message ?? ""}
                  </td>
                  <td className={CELL_CLASS}>
                    {formatOlympusTime(condition.lastTransitionTime) ?? ""}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </OlympusDetailSection>
  );
}
