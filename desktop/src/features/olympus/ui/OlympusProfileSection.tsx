import * as React from "react";
import { ArrowUpRight, FileText, Pencil } from "lucide-react";

import { useAppNavigation } from "@/app/navigation/useAppNavigation";
import {
  OLYMPUS_EFFORTS,
  olympusEffectiveSpec,
} from "@/features/agents/lib/olympusAgents";
import {
  type OlympusChange,
  olympusRequestKey,
  useOlympusRequestState,
} from "@/features/agents/lib/olympusChangeRequests";
import { OlympusRequestStatus } from "@/features/agents/ui/OlympusAgentParts";
import { useOlympusAgents } from "@/features/agents/useOlympusAgents";
import { useUsersBatchQuery } from "@/features/profile/hooks";
import { cn } from "@/shared/lib/cn";
import { useNow } from "@/shared/lib/useNow";
import { Button } from "@/shared/ui/button";
import { PanelSectionGroup } from "@/shared/ui/PanelSectionGroup";
import { PubKey } from "@/shared/ui/PubKey";
import { olympusModelChoices } from "../lib/olympusModels";
import { olympusFieldLocked } from "../lib/olympusOwnership";
import {
  type OlympusProfileMatch,
  olympusLastError,
} from "../lib/olympusProfile";
import { listOlympusSchedules } from "../lib/olympusSchedules";
import {
  OlympusAgentEditor,
  olympusEditableSpec,
  useOlympusSpecSave,
} from "./OlympusAgentEditor";
import { OlympusContextGauge } from "./OlympusContextGauge";
import { OlympusAgentUsage } from "./olympusMounts";
import {
  formatOlympusAgo,
  formatOlympusIn,
  OlympusChip,
  OlympusGitLock,
  OlympusMasterChip,
  OlympusPhase,
  OlympusRunResult,
  OlympusSelect,
} from "./OlympusParts";

const OTHER_MODEL = "\u0000other";
const QUICK_SELECT = "h-7 w-auto max-w-full gap-1.5 px-2 text-sm";

function Row({
  children,
  label,
  locked,
  testId,
}: {
  children: React.ReactNode;
  label: string;
  locked?: boolean;
  testId?: string;
}) {
  return (
    <div
      className="grid min-h-10 grid-cols-[6.5rem_minmax(0,1fr)] items-center gap-3 px-4 py-2"
      data-testid={testId}
    >
      <dt className="flex items-center gap-1.5 text-xs text-muted-foreground">
        {label}
        {locked ? <OlympusGitLock field={label} /> : null}
      </dt>
      <dd className="min-w-0 break-words text-sm text-foreground">
        {children}
      </dd>
    </div>
  );
}

function Muted({ children }: { children: React.ReactNode }) {
  return <span className="text-muted-foreground">{children}</span>;
}

export function OlympusProfileSection({
  match,
}: {
  match: OlympusProfileMatch;
}) {
  const { agent, group } = match;
  const workspace = group.workspace;
  const olympus = useOlympusAgents();
  const { goOlympusAgent } = useAppNavigation();
  const key = olympusRequestKey(agent.workspace, agent.name);
  const request = useOlympusRequestState(key);
  const pending = request?.phase === "pending";
  const [editing, setEditing] = React.useState(false);
  const send = React.useCallback(
    (change: OlympusChange) =>
      olympus.submitChange(
        key,
        {
          operator: agent.author,
          workspace: agent.workspace,
          agent: agent.name,
        },
        change,
      ),
    [agent.author, agent.name, agent.workspace, key, olympus],
  );
  const spec = olympusEffectiveSpec(agent);
  const legacy = agent.gitopsFields === null;
  const locked = (field: string) => olympusFieldLocked(agent, `spec.${field}`);
  const quick = (field: string) => !legacy && !locked(field) && !pending;
  const saver = useOlympusSpecSave(agent, send);
  const responders = useUsersBatchQuery(spec.respondTo, {
    enabled: spec.respondTo.length > 0,
  }).data?.profiles;
  const choices = olympusModelChoices(olympus.groups, workspace, spec.pool);
  const provider = workspace?.providers.find((item) => item.name === spec.pool);
  const lastError = olympusLastError(agent.conditions);

  const setField = (field: "model" | "effort", value: string) => {
    const after = olympusEditableSpec(agent);
    if (value) after[field] = value;
    else delete after[field];
    saver.save(after);
  };

  const modelOptions = [
    ...(spec.model && !choices.models.includes(spec.model)
      ? [
          {
            value: spec.model,
            label: choices.restricted
              ? `${spec.model} (not allowed)`
              : spec.model,
          },
        ]
      : []),
    ...choices.models.map((item) => ({ value: item, label: item })),
    ...(choices.restricted
      ? []
      : [{ value: OTHER_MODEL, label: "Other model…" }]),
  ];

  return (
    <div className="space-y-3" data-testid="olympus-profile">
      <PanelSectionGroup
        headerAction={
          <div className="flex items-center gap-1">
            <Button
              aria-label="Open in Olympus"
              onClick={() => void goOlympusAgent(agent.workspace, agent.name)}
              size="xs"
              title="Open in Olympus"
              type="button"
              variant="ghost"
            >
              <ArrowUpRight />
              Olympus
            </Button>
            <Button
              data-testid="olympus-profile-edit"
              disabled={pending}
              onClick={() => setEditing(true)}
              size="xs"
              type="button"
              variant="outline"
            >
              <Pencil />
              Edit
            </Button>
          </div>
        }
        testId="olympus-profile-section"
        title="Olympus"
      >
        <dl className="divide-y divide-border/55">
          <div
            className="space-y-2 px-4 py-3"
            data-testid="olympus-profile-status"
          >
            <div className="flex flex-wrap items-center gap-1.5">
              <OlympusPhase phase={agent.phase} />
              {agent.role === "master" ? <OlympusMasterChip /> : null}
              <span className="ml-auto text-xs text-muted-foreground">
                {agent.lastActivity
                  ? `Active ${formatOlympusAgo(agent.lastActivity)}`
                  : "No activity"}
              </span>
            </div>
            {lastError ? (
              <div
                className={cn(
                  "space-y-0.5 text-xs",
                  agent.phase === "Suspended"
                    ? "text-muted-foreground"
                    : "text-destructive",
                )}
                data-testid="olympus-profile-error"
                title={lastError.detail ?? undefined}
              >
                <p className="font-medium">{lastError.title}</p>
                {lastError.detail ? (
                  <p className="line-clamp-3 break-words">{lastError.detail}</p>
                ) : null}
              </div>
            ) : null}
          </div>
          <OlympusContextGauge
            agentPubkey={agent.publicKey}
            className="px-4 py-3"
            limit={1}
          />
          <Row label="Workspace" testId="olympus-profile-workspace">
            {agent.workspace}
            <Muted>
              {" "}
              · {agent.name}
              {workspace?.suspend ? " · suspended" : ""}
            </Muted>
          </Row>
          <Row label="Role">
            {agent.role === "master"
              ? "Master"
              : (agent.role ?? <Muted>Agent</Muted>)}
          </Row>
          <Row label="Harness" locked={locked("harness")}>
            {spec.harness || <Muted>Template default</Muted>}
          </Row>
          <Row
            label="Model"
            locked={locked("model")}
            testId="olympus-profile-model"
          >
            {quick("model") ? (
              <OlympusSelect
                className={QUICK_SELECT}
                label="Model"
                onChange={(value) =>
                  value === OTHER_MODEL
                    ? setEditing(true)
                    : setField("model", value)
                }
                options={modelOptions}
                value={spec.model}
              />
            ) : (
              <span>{spec.model}</span>
            )}
          </Row>
          <Row label="Provider" locked={locked("pool")}>
            <span>{spec.pool}</span>
            {provider?.description ? (
              <span className="mt-0.5 line-clamp-2 block text-xs text-muted-foreground">
                {provider.description}
              </span>
            ) : null}
          </Row>
          <Row
            label="Effort"
            locked={locked("effort")}
            testId="olympus-profile-effort"
          >
            {quick("effort") ? (
              <OlympusSelect
                className={QUICK_SELECT}
                label="Effort"
                onChange={(value) => setField("effort", value)}
                options={[
                  { value: "", label: "Default" },
                  ...OLYMPUS_EFFORTS.map((item) => ({
                    value: item,
                    label: item,
                  })),
                ]}
                value={agent.spec.effort ?? ""}
              />
            ) : (
              (spec.effort ?? <Muted>Default</Muted>)
            )}
          </Row>
          <Row label="Responds to" locked={locked("respondTo")}>
            {spec.respondTo.length > 0 ? (
              <span className="flex flex-col items-start gap-0.5">
                {spec.respondTo.map((item) => {
                  const name =
                    responders?.[item]?.displayName?.trim() ||
                    responders?.[item]?.name?.trim();
                  return name ? (
                    <span key={item} title={item}>
                      {name}
                    </span>
                  ) : (
                    <PubKey key={item} pubkey={item} />
                  );
                })}
              </span>
            ) : (
              <Muted>Owner and scheduler only</Muted>
            )}
          </Row>
          <Row label="MCP servers" locked={locked("mcpServers")}>
            {spec.mcpServers.length > 0 ? (
              <span className="flex flex-wrap gap-1">
                {spec.mcpServers.map((server) => (
                  <OlympusChip
                    key={server.name}
                    title={server.tools ? server.tools.join(", ") : "All tools"}
                  >
                    {server.name}
                    {server.tools ? ` · ${server.tools.length}` : ""}
                  </OlympusChip>
                ))}
              </span>
            ) : (
              <Muted>None</Muted>
            )}
          </Row>
          <Row label="Memory" locked={locked("memory")}>
            {spec.memory ? `Bank ${spec.memory.bank}` : <Muted>Off</Muted>}
          </Row>
          <Row label="Instructions" testId="olympus-profile-instructions">
            {agent.instructionsFile ? (
              <button
                className="group flex min-w-0 items-center gap-1.5 text-left font-mono text-xs hover:underline disabled:cursor-not-allowed disabled:opacity-60"
                disabled={pending}
                onClick={() => setEditing(true)}
                title={`Edit ${agent.instructionsFile.repo}/${agent.instructionsFile.path}`}
                type="button"
              >
                <FileText
                  aria-hidden
                  className="h-3.5 w-3.5 shrink-0 text-muted-foreground"
                />
                <span className="truncate">
                  {agent.instructionsFile.repo}/{agent.instructionsFile.path}
                </span>
              </button>
            ) : spec.instructionsFrom ? (
              <span className="font-mono text-xs">
                {spec.instructionsFrom.skillsRepo}/{spec.instructionsFrom.path}
              </span>
            ) : spec.instructions ? (
              <Muted>Inline text</Muted>
            ) : (
              <Muted>None</Muted>
            )}
          </Row>
        </dl>
      </PanelSectionGroup>
      <OlympusRequestStatus state={request} testId="olympus-profile-request" />
      <OlympusProfileSchedules match={match} />
      <OlympusAgentUsage agent={agent.name} workspace={agent.workspace} />
      {editing ? (
        <OlympusAgentEditor
          agent={agent}
          onOpenChange={setEditing}
          send={send}
          workspace={workspace}
        />
      ) : null}
      {saver.dialog}
    </div>
  );
}

function OlympusProfileSchedules({ match }: { match: OlympusProfileMatch }) {
  const now = useNow(60_000);
  const rows = React.useMemo(
    () =>
      listOlympusSchedules([match.group], now).filter(
        (row) => row.agent.d === match.agent.d,
      ),
    [match, now],
  );
  if (rows.length === 0) return null;
  return (
    <PanelSectionGroup testId="olympus-profile-schedules" title="Schedules">
      <ul className="divide-y divide-border/55">
        {rows.map(({ key, nextRun, schedule, suspended }) => (
          <li
            className="flex items-center gap-3 px-4 py-2"
            data-testid={`olympus-profile-schedule-${schedule.name}`}
            key={key}
          >
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-medium">{schedule.name}</p>
              <p className="truncate text-xs text-muted-foreground">
                {suspended
                  ? "Suspended"
                  : (formatOlympusIn(nextRun) ?? "No next run")}
                {schedule.lastRunTime
                  ? ` · last ${formatOlympusAgo(schedule.lastRunTime)}`
                  : ""}
              </p>
            </div>
            <OlympusRunResult result={schedule.lastResult} />
          </li>
        ))}
      </ul>
    </PanelSectionGroup>
  );
}
