import * as React from "react";

import {
  OLYMPUS_AGENT_NAME_PATTERN,
  OLYMPUS_HARNESSES,
  type OlympusWorkspace,
  olympusModelOptions,
} from "@/features/agents/lib/olympusAgents";
import type { OlympusChange } from "@/features/agents/lib/olympusChangeRequests";
import { Button } from "@/shared/ui/button";
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
  OlympusEffortField,
  OlympusModelField,
} from "./OlympusAgentChangeControls";
import { OLYMPUS_SELECT_CLASS } from "./OlympusAgentParts";

export function OlympusNewAgentDialog({
  existingNames,
  onCreate,
  onOpenChange,
  workspace,
}: {
  existingNames: string[];
  onCreate: (name: string, change: OlympusChange) => void;
  onOpenChange: (open: boolean) => void;
  workspace: OlympusWorkspace;
}) {
  const formId = React.useId();
  const [name, setName] = React.useState("");
  const [harness, setHarness] = React.useState<string>(OLYMPUS_HARNESSES[0]);
  const [pool, setPool] = React.useState(workspace.providers[0]?.name ?? "");
  const [model, setModel] = React.useState(
    workspace.providers[0]?.models[0] ?? "",
  );
  const [effort, setEffort] = React.useState("");
  const [instructions, setInstructions] = React.useState("");
  const models = olympusModelOptions(workspace, pool);
  const nameError =
    name.length === 0
      ? null
      : !OLYMPUS_AGENT_NAME_PATTERN.test(name)
        ? "Use lowercase letters, digits, and hyphens (max. 63). Start and end with a letter or digit."
        : existingNames.includes(name)
          ? "An agent with this name exists in this workspace."
          : null;
  const canSubmit =
    name.length > 0 && !nameError && pool.length > 0 && model.trim().length > 0;

  return (
    <Dialog onOpenChange={onOpenChange} open>
      <DialogContent
        className="max-w-xl overflow-hidden p-0"
        data-testid="olympus-new-agent-dialog"
      >
        <form
          className="flex max-h-[85vh] flex-col"
          onSubmit={(event) => {
            event.preventDefault();
            if (!canSubmit) return;
            onCreate(name, {
              action: "create",
              harness,
              pool,
              model: model.trim(),
              ...(effort ? { effort } : {}),
              ...(instructions.trim() ? { instructions } : {}),
            });
          }}
        >
          <DialogHeader className="shrink-0 border-b border-border/60 px-6 py-5 pr-14">
            <DialogTitle>New agent in {workspace.name}</DialogTitle>
            <DialogDescription>
              Hephaestus creates the agent in the cluster and enrolls it.
            </DialogDescription>
          </DialogHeader>
          <div className="min-h-0 flex-1 space-y-4 overflow-y-auto px-6 py-5">
            <div className="space-y-1.5">
              <label className="text-sm font-medium" htmlFor={`${formId}-name`}>
                Name
              </label>
              <Input
                aria-describedby={
                  nameError ? `${formId}-name-error` : `${formId}-name-hint`
                }
                aria-invalid={nameError ? true : undefined}
                autoComplete="off"
                id={`${formId}-name`}
                onChange={(event) => setName(event.target.value)}
                value={name}
              />
              {nameError ? null : (
                <p
                  className="text-xs text-muted-foreground"
                  id={`${formId}-name-hint`}
                >
                  Lowercase letters, digits, and hyphens.
                </p>
              )}
              {nameError ? (
                <p
                  className="text-xs text-destructive"
                  id={`${formId}-name-error`}
                >
                  {nameError}
                </p>
              ) : null}
            </div>
            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-1.5">
                <label
                  className="text-sm font-medium"
                  htmlFor={`${formId}-harness`}
                >
                  Harness
                </label>
                <select
                  className={OLYMPUS_SELECT_CLASS}
                  id={`${formId}-harness`}
                  onChange={(event) => setHarness(event.target.value)}
                  value={harness}
                >
                  {OLYMPUS_HARNESSES.map((value) => (
                    <option key={value} value={value}>
                      {value}
                    </option>
                  ))}
                </select>
              </div>
              <div className="space-y-1.5">
                <label
                  className="text-sm font-medium"
                  htmlFor={`${formId}-pool`}
                >
                  Pool
                </label>
                <select
                  className={OLYMPUS_SELECT_CLASS}
                  disabled={workspace.providers.length === 0}
                  id={`${formId}-pool`}
                  onChange={(event) => {
                    setPool(event.target.value);
                    setModel(
                      olympusModelOptions(workspace, event.target.value)[0] ??
                        "",
                    );
                  }}
                  value={pool}
                >
                  {workspace.providers.length === 0 ? (
                    <option value="">No pools in this workspace</option>
                  ) : null}
                  {workspace.providers.map((provider) => (
                    <option key={provider.name} value={provider.name}>
                      {provider.name}
                    </option>
                  ))}
                </select>
              </div>
              <div className="space-y-1.5">
                <label
                  className="text-sm font-medium"
                  htmlFor={`${formId}-model`}
                >
                  Model
                </label>
                <OlympusModelField
                  disabled={false}
                  id={`${formId}-model`}
                  models={models}
                  onChange={setModel}
                  value={model}
                />
              </div>
              <div className="space-y-1.5">
                <label
                  className="text-sm font-medium"
                  htmlFor={`${formId}-effort`}
                >
                  Effort
                </label>
                <OlympusEffortField
                  disabled={false}
                  id={`${formId}-effort`}
                  onChange={setEffort}
                  value={effort}
                />
              </div>
            </div>
            <div className="space-y-1.5">
              <label
                className="text-sm font-medium"
                htmlFor={`${formId}-instructions`}
              >
                Instructions
              </label>
              <Textarea
                className="min-h-32 font-mono text-xs"
                id={`${formId}-instructions`}
                onChange={(event) => setInstructions(event.target.value)}
                value={instructions}
              />
            </div>
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
  );
}
