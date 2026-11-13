import * as React from "react";

import {
  OLYMPUS_AGENT_NAME_PATTERN,
  OLYMPUS_EFFORTS,
  OLYMPUS_HARNESSES,
  type OlympusAgent,
  type OlympusWorkspaceGroup,
  olympusModelOptions,
} from "@/features/agents/lib/olympusAgents";
import { useOlympusAgents } from "@/features/agents/useOlympusAgents";
import { Button } from "@/shared/ui/button";
import { Checkbox } from "@/shared/ui/checkbox";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/shared/ui/dialog";
import { Input } from "@/shared/ui/input";
import { Textarea } from "@/shared/ui/textarea";
import {
  olympusCreateChange,
  type OlympusEgressChoice,
  type OlympusMemoryChoice,
  type OlympusNewAgentDraft,
  olympusPoolsFor,
  type OlympusStart,
  olympusStartDraft,
} from "../lib/olympusNewAgent";
import { OlympusSelect } from "./OlympusParts";
import { useOlympusRiskGate } from "./OlympusRiskGate";

function startKey(start: OlympusStart) {
  if (start.kind === "template") return `template:${start.template.name}`;
  if (start.kind === "clone") return `clone:${start.agent.name}`;
  return "blank";
}

function Row({
  children,
  htmlFor,
  label,
}: {
  children: React.ReactNode;
  htmlFor: string;
  label: string;
}) {
  return (
    <div className="space-y-1.5">
      <label className="text-sm font-medium" htmlFor={htmlFor}>
        {label}
      </label>
      {children}
    </div>
  );
}

export function OlympusNewAgentDialog({
  group,
  onOpenChange,
  requestKey,
  source,
}: {
  group: OlympusWorkspaceGroup;
  onOpenChange: (open: boolean) => void;
  requestKey: string;
  source?: OlympusAgent;
}) {
  const olympus = useOlympusAgents();
  const gate = useOlympusRiskGate();
  const id = React.useId();
  const workspace = group.workspace;
  const legacy = workspace?.gitopsFields === null;
  const starts = React.useMemo<OlympusStart[]>(() => {
    if (legacy) return [{ kind: "blank" }];
    return [
      { kind: "blank" },
      ...(workspace?.templates ?? []).map(
        (template) => ({ kind: "template", template }) as const,
      ),
      ...group.agents.map((agent) => ({ kind: "clone", agent }) as const),
    ];
  }, [group.agents, legacy, workspace?.templates]);
  const [start, setStart] = React.useState<OlympusStart>(
    source && !legacy ? { kind: "clone", agent: source } : { kind: "blank" },
  );
  const [draft, setDraft] = React.useState<OlympusNewAgentDraft>(() =>
    olympusStartDraft(start, workspace),
  );
  const update = (patch: Partial<OlympusNewAgentDraft>) =>
    setDraft((current) => ({ ...current, ...patch }));
  const pools = olympusPoolsFor(workspace, draft.harness);
  const models = olympusModelOptions(workspace, draft.pool);
  const servers = (workspace?.mcpServers ?? []).filter(
    (name) => name !== "hindsight",
  );
  const existing = group.agents.map((agent) => agent.name);
  const nameError =
    draft.name.length === 0
      ? null
      : !OLYMPUS_AGENT_NAME_PATTERN.test(draft.name) ||
          draft.name.startsWith("olympus-")
        ? "Use lowercase letters, digits, and hyphens (max. 63). Start and end with a letter or digit."
        : existing.includes(draft.name)
          ? "An agent with this name exists in this workspace."
          : null;
  const needsRuntime = start.kind !== "template";
  const canSubmit =
    draft.name.length > 0 &&
    !nameError &&
    (!needsRuntime || (draft.pool.length > 0 && draft.model.trim().length > 0));

  const choose = (key: string) => {
    const next = starts.find((item) => startKey(item) === key);
    if (!next) return;
    setStart(next);
    setDraft({ ...olympusStartDraft(next, workspace), name: draft.name });
  };

  const submit = () => {
    if (!canSubmit) return;
    const { change, risks } = olympusCreateChange(start, draft, legacy);
    gate.guard(draft.name, risks, (confirmed) => {
      const signed =
        confirmed && "spec" in change
          ? { ...change, highRisk: true as const }
          : change;
      void olympus.submitChange(
        requestKey,
        { operator: group.author, workspace: group.name, agent: draft.name },
        signed,
      );
      onOpenChange(false);
    });
  };

  return (
    <>
      <Dialog onOpenChange={onOpenChange} open>
        <DialogContent
          className="max-w-xl overflow-hidden p-0"
          data-testid="olympus-new-agent-dialog"
        >
          <form
            className="flex max-h-[85vh] flex-col"
            onSubmit={(event) => {
              event.preventDefault();
              submit();
            }}
          >
            <DialogHeader className="shrink-0 border-b border-border/60 px-6 py-5 pr-14">
              <DialogTitle>New agent in {group.name}</DialogTitle>
              <DialogDescription>
                Hephaestus creates the agent in the cluster. It is not in
                gitops-home.
              </DialogDescription>
            </DialogHeader>
            <div className="min-h-0 flex-1 space-y-4 overflow-y-auto px-6 py-5">
              {starts.length > 1 ? (
                <Row htmlFor={`${id}-start`} label="Start from">
                  <OlympusSelect
                    id={`${id}-start`}
                    label="Start from"
                    onChange={choose}
                    options={starts.map((item) => ({
                      value: startKey(item),
                      label:
                        item.kind === "template"
                          ? `Template ${item.template.name}`
                          : item.kind === "clone"
                            ? `Copy of ${item.agent.name}`
                            : "Blank agent",
                    }))}
                    value={startKey(start)}
                  />
                </Row>
              ) : null}
              <div className="grid gap-4 sm:grid-cols-2">
                <Row htmlFor={`${id}-name`} label="Name">
                  <Input
                    aria-describedby={
                      nameError ? `${id}-name-error` : undefined
                    }
                    aria-invalid={nameError ? true : undefined}
                    autoFocus
                    id={`${id}-name`}
                    maxLength={63}
                    onChange={(event) => update({ name: event.target.value })}
                    placeholder="researcher"
                    value={draft.name}
                  />
                  {nameError ? (
                    <p
                      className="text-xs text-destructive"
                      id={`${id}-name-error`}
                    >
                      {nameError}
                    </p>
                  ) : null}
                </Row>
                {legacy ? null : (
                  <Row htmlFor={`${id}-display`} label="Display name">
                    <Input
                      id={`${id}-display`}
                      maxLength={64}
                      onChange={(event) =>
                        update({ displayName: event.target.value })
                      }
                      placeholder={draft.name || "Optional"}
                      value={draft.displayName}
                    />
                  </Row>
                )}
              </div>
              <div className="grid gap-4 sm:grid-cols-2">
                <Row htmlFor={`${id}-harness`} label="Harness">
                  <OlympusSelect
                    id={`${id}-harness`}
                    label="Harness"
                    onChange={(harness) => {
                      const pool = olympusPoolsFor(workspace, harness)[0];
                      update({
                        harness,
                        pool: pool?.name ?? "",
                        model: pool?.models[0] ?? "",
                      });
                    }}
                    options={OLYMPUS_HARNESSES.map((item) => ({
                      value: item,
                      label: item,
                    }))}
                    value={draft.harness}
                  />
                </Row>
                <Row htmlFor={`${id}-pool`} label="Model pool">
                  <OlympusSelect
                    id={`${id}-pool`}
                    label="Model pool"
                    onChange={(pool) =>
                      update({
                        pool,
                        model: olympusModelOptions(workspace, pool)[0] ?? "",
                      })
                    }
                    options={pools.map((pool) => ({
                      value: pool.name,
                      label: pool.name,
                    }))}
                    placeholder={
                      pools.length === 0 ? "No pool for this harness" : "Choose"
                    }
                    value={draft.pool}
                  />
                </Row>
                <Row htmlFor={`${id}-model`} label="Model">
                  {models.length > 0 ? (
                    <OlympusSelect
                      id={`${id}-model`}
                      label="Model"
                      onChange={(model) => update({ model })}
                      options={models.map((model) => ({
                        value: model,
                        label: model,
                      }))}
                      value={draft.model}
                    />
                  ) : (
                    <Input
                      id={`${id}-model`}
                      onChange={(event) =>
                        update({ model: event.target.value })
                      }
                      value={draft.model}
                    />
                  )}
                </Row>
                <Row htmlFor={`${id}-effort`} label="Effort">
                  <OlympusSelect
                    id={`${id}-effort`}
                    label="Effort"
                    onChange={(effort) => update({ effort })}
                    options={[
                      { value: "", label: "Default" },
                      ...OLYMPUS_EFFORTS.map((effort) => ({
                        value: effort,
                        label: effort,
                      })),
                    ]}
                    value={draft.effort}
                  />
                </Row>
              </div>
              {legacy ? null : (
                <>
                  <fieldset className="space-y-2">
                    <legend className="text-sm font-medium">MCP servers</legend>
                    {servers.length === 0 ? (
                      <p className="text-xs text-muted-foreground">
                        This workspace has no MCP servers.
                      </p>
                    ) : (
                      <div className="flex flex-wrap gap-x-4 gap-y-2">
                        {servers.map((name) => (
                          <label
                            className="flex items-center gap-2 text-sm"
                            htmlFor={`${id}-mcp-${name}`}
                            key={name}
                          >
                            <Checkbox
                              checked={draft.mcpServers.includes(name)}
                              id={`${id}-mcp-${name}`}
                              onCheckedChange={(checked) =>
                                update({
                                  mcpServers: checked
                                    ? [...draft.mcpServers, name]
                                    : draft.mcpServers.filter(
                                        (item) => item !== name,
                                      ),
                                })
                              }
                            />
                            {name}
                          </label>
                        ))}
                      </div>
                    )}
                  </fieldset>
                  <div className="grid gap-4 sm:grid-cols-2">
                    <Row htmlFor={`${id}-memory`} label="Memory">
                      <OlympusSelect
                        id={`${id}-memory`}
                        label="Memory"
                        onChange={(memory) =>
                          update({ memory: memory as OlympusMemoryChoice })
                        }
                        options={[
                          { value: "", label: "Off" },
                          { value: "private", label: "Private bank" },
                          { value: "workspace", label: "Workspace bank" },
                        ]}
                        value={draft.memory}
                      />
                    </Row>
                    <Row htmlFor={`${id}-egress`} label="Network egress">
                      <OlympusSelect
                        id={`${id}-egress`}
                        label="Network egress"
                        onChange={(egress) =>
                          update({ egress: egress as OlympusEgressChoice })
                        }
                        options={[
                          { value: "", label: "Only granted services" },
                          { value: "cluster", label: "Cluster services" },
                          {
                            value: "internet",
                            label: "Open internet (high risk)",
                          },
                        ]}
                        value={draft.egress}
                      />
                    </Row>
                  </div>
                </>
              )}
              <Row htmlFor={`${id}-instructions`} label="Instructions">
                <Textarea
                  className="min-h-32 font-mono text-xs"
                  disabled={
                    start.kind === "clone" &&
                    start.agent.spec.instructionsFrom !== null
                  }
                  id={`${id}-instructions`}
                  onChange={(event) =>
                    update({ instructions: event.target.value })
                  }
                  placeholder={
                    start.kind === "clone" &&
                    start.agent.spec.instructionsFrom !== null
                      ? "The copy reads the instructions from the same skills repository."
                      : "What the agent does"
                  }
                  value={draft.instructions}
                />
              </Row>
            </div>
            <DialogFooter className="shrink-0 border-t border-border/60 px-6 py-4">
              <Button
                onClick={() => onOpenChange(false)}
                type="button"
                variant="outline"
              >
                Cancel
              </Button>
              <Button disabled={!canSubmit} type="submit">
                Create agent
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
      {gate.dialog}
    </>
  );
}
