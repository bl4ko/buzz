import * as React from "react";
import { Pause, Pencil, Play, Plus, Trash2, X } from "lucide-react";

import {
  OLYMPUS_EFFORTS,
  type OlympusAgent,
  type OlympusWorkspace,
  olympusAddableMcpServers,
  olympusModelOptions,
} from "@/features/agents/lib/olympusAgents";
import type { OlympusChange } from "@/features/agents/lib/olympusChangeRequests";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/shared/ui/alert-dialog";
import { Button } from "@/shared/ui/button";
import { Input } from "@/shared/ui/input";
import { Textarea } from "@/shared/ui/textarea";
import { OlympusSelect } from "@/features/olympus/ui/OlympusParts";
import { OLYMPUS_SELECT_CLASS } from "./OlympusAgentParts";

type Send = (change: OlympusChange) => void;

export function OlympusAgentActions({
  agent,
  disabled,
  isEditing,
  onEdit,
  send,
}: {
  agent: OlympusAgent;
  disabled: boolean;
  isEditing: boolean;
  onEdit: () => void;
  send: Send;
}) {
  const [confirmDelete, setConfirmDelete] = React.useState(false);
  const suspended = agent.spec.suspend;
  return (
    <>
      <Button
        disabled={disabled}
        onClick={() => send({ action: suspended ? "resume" : "suspend" })}
        size="sm"
        type="button"
        variant="outline"
      >
        {suspended ? <Play /> : <Pause />}
        {suspended ? "Resume" : "Suspend"}
      </Button>
      <Button
        aria-expanded={isEditing}
        disabled={disabled}
        onClick={onEdit}
        size="sm"
        type="button"
        variant="outline"
      >
        <Pencil />
        Edit
      </Button>
      <Button
        className="text-destructive hover:text-destructive"
        disabled={disabled}
        onClick={() => setConfirmDelete(true)}
        size="sm"
        type="button"
        variant="outline"
      >
        <Trash2 />
        Delete
      </Button>
      <AlertDialog onOpenChange={setConfirmDelete} open={confirmDelete}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete {agent.name}?</AlertDialogTitle>
            <AlertDialogDescription>
              Hephaestus deletes the agent {agent.name} in workspace{" "}
              {agent.workspace}. You cannot undo this.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel asChild>
              <Button type="button" variant="outline">
                Cancel
              </Button>
            </AlertDialogCancel>
            <AlertDialogAction asChild>
              <Button
                onClick={() => send({ action: "delete" })}
                type="button"
                variant="destructive"
              >
                Delete agent
              </Button>
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}

export function OlympusModelField({
  disabled,
  id,
  models,
  onChange,
  value,
}: {
  disabled: boolean;
  id: string;
  models: string[];
  onChange: (value: string) => void;
  value: string;
}) {
  if (models.length === 0) {
    return (
      <Input
        disabled={disabled}
        id={id}
        onChange={(event) => onChange(event.target.value)}
        value={value}
      />
    );
  }
  const options =
    models.includes(value) || !value ? models : [value, ...models];
  return (
    <select
      className={OLYMPUS_SELECT_CLASS}
      disabled={disabled}
      id={id}
      onChange={(event) => onChange(event.target.value)}
      value={value}
    >
      {value ? null : <option value="">Choose a model</option>}
      {options.map((model) => (
        <option key={model} value={model}>
          {model}
        </option>
      ))}
    </select>
  );
}

export function OlympusEffortField({
  disabled,
  id,
  onChange,
  value,
}: {
  disabled: boolean;
  id: string;
  onChange: (value: string) => void;
  value: string;
}) {
  return (
    <select
      className={OLYMPUS_SELECT_CLASS}
      disabled={disabled}
      id={id}
      onChange={(event) => onChange(event.target.value)}
      value={value}
    >
      <option value="">None</option>
      {OLYMPUS_EFFORTS.map((effort) => (
        <option key={effort} value={effort}>
          {effort}
        </option>
      ))}
    </select>
  );
}

export function olympusUpdateChange(
  agent: OlympusAgent,
  draft: { model: string; effort: string; instructions: string },
): OlympusChange | null {
  const change: Extract<OlympusChange, { action: "update" }> = {
    action: "update",
  };
  const model = draft.model.trim();
  if (model && model !== agent.spec.model) change.model = model;
  const effort = draft.effort || null;
  if (effort !== agent.spec.effort) change.effort = effort;
  const instructions = draft.instructions.trim() ? draft.instructions : null;
  if (instructions !== agent.spec.instructions) {
    change.instructions = instructions;
  }
  return Object.keys(change).length > 1 ? change : null;
}

export function OlympusAgentEditForm({
  agent,
  disabled,
  onCancel,
  send,
  workspace,
}: {
  agent: OlympusAgent;
  disabled: boolean;
  onCancel: () => void;
  send: Send;
  workspace: OlympusWorkspace | null;
}) {
  const formId = React.useId();
  const [model, setModel] = React.useState(agent.spec.model);
  const [effort, setEffort] = React.useState(agent.spec.effort ?? "");
  const [instructions, setInstructions] = React.useState(
    agent.spec.instructions ?? "",
  );
  const change = olympusUpdateChange(agent, { model, effort, instructions });
  return (
    <form
      aria-label={`Edit ${agent.name}`}
      className="space-y-4 rounded-2xl border border-border/70 bg-muted/20 p-4"
      data-testid="olympus-agent-edit-form"
      onSubmit={(event) => {
        event.preventDefault();
        if (change) {
          send(change);
          onCancel();
        }
      }}
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-1.5">
          <label className="text-sm font-medium" htmlFor={`${formId}-model`}>
            Model
          </label>
          <OlympusModelField
            disabled={disabled}
            id={`${formId}-model`}
            models={olympusModelOptions(workspace, agent.spec.pool)}
            onChange={setModel}
            value={model}
          />
        </div>
        <div className="space-y-1.5">
          <label className="text-sm font-medium" htmlFor={`${formId}-effort`}>
            Effort
          </label>
          <OlympusEffortField
            disabled={disabled}
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
          className="min-h-40 font-mono text-xs"
          disabled={disabled}
          id={`${formId}-instructions`}
          onChange={(event) => setInstructions(event.target.value)}
          value={instructions}
        />
      </div>
      <div className="flex justify-end gap-2">
        <Button onClick={onCancel} size="sm" type="button" variant="outline">
          Cancel
        </Button>
        <Button disabled={disabled || !change} size="sm" type="submit">
          Save changes
        </Button>
      </div>
    </form>
  );
}

export function OlympusMcpControls({
  agent,
  disabled,
  send,
  workspace,
}: {
  agent: OlympusAgent;
  disabled: boolean;
  send: Send;
  workspace: OlympusWorkspace | null;
}) {
  const selectId = React.useId();
  const addable = olympusAddableMcpServers(workspace, agent);
  const [server, setServer] = React.useState("");
  const selected = addable.includes(server) ? server : (addable[0] ?? "");
  return (
    <div className="space-y-2">
      {agent.spec.mcpServers.length > 0 ? (
        <ul className="divide-y divide-border/40 rounded-lg border border-border/60">
          {agent.spec.mcpServers.map((entry) => (
            <li
              className="flex items-center justify-between gap-3 px-3 py-2"
              key={entry.name}
            >
              <span className="min-w-0 text-sm text-foreground">
                <span className="font-medium">{entry.name}</span>
                <span className="block text-xs text-muted-foreground">
                  {entry.tools ? entry.tools.join(", ") : "All tools"}
                </span>
              </span>
              <Button
                aria-label={`Remove MCP server ${entry.name}`}
                disabled={disabled}
                onClick={() =>
                  send({ action: "remove-mcp", server: entry.name })
                }
                size="icon-xs"
                type="button"
                variant="ghost"
              >
                <X />
              </Button>
            </li>
          ))}
        </ul>
      ) : (
        <p className="text-xs text-muted-foreground">No MCP servers.</p>
      )}
      {addable.length > 0 ? (
        <div className="flex flex-wrap items-end gap-2">
          <div className="min-w-48 flex-1 space-y-1.5">
            <label className="text-xs text-muted-foreground" htmlFor={selectId}>
              MCP server to add
            </label>
            <OlympusSelect
              disabled={disabled}
              id={selectId}
              label="MCP server to add"
              onChange={setServer}
              options={addable.map((name) => ({ value: name, label: name }))}
              value={selected}
            />
          </div>
          <Button
            disabled={disabled || !selected}
            onClick={() =>
              send({ action: "add-mcp", server: { name: selected } })
            }
            size="sm"
            type="button"
            variant="outline"
          >
            <Plus />
            Add MCP server
          </Button>
        </div>
      ) : null}
    </div>
  );
}

export function OlympusMemoryControls({
  agent,
  disabled,
  send,
}: {
  agent: OlympusAgent;
  disabled: boolean;
  send: Send;
}) {
  const selectId = React.useId();
  const current = agent.spec.memory?.bank ?? "";
  const [bank, setBank] = React.useState(
    current === "workspace" ? "workspace" : "private",
  );
  return (
    <div className="space-y-2">
      <p className="text-xs text-muted-foreground">
        {agent.spec.memory
          ? `Memory bank: ${agent.spec.memory.bank}.`
          : "Memory is off for this agent."}
      </p>
      <div className="flex flex-wrap items-end gap-2">
        <div className="min-w-48 flex-1 space-y-1.5">
          <label className="text-xs text-muted-foreground" htmlFor={selectId}>
            Memory bank
          </label>
          <OlympusSelect
            disabled={disabled}
            id={selectId}
            label="Memory bank"
            onChange={setBank}
            options={[
              { value: "private", label: "private" },
              { value: "workspace", label: "workspace" },
            ]}
            value={bank}
          />
        </div>
        <Button
          disabled={disabled || bank === current}
          onClick={() =>
            send({
              action: "set-memory",
              memory: { bank: bank === "workspace" ? "workspace" : "private" },
            })
          }
          size="sm"
          type="button"
          variant="outline"
        >
          Set memory
        </Button>
        {agent.spec.memory ? (
          <Button
            disabled={disabled}
            onClick={() => send({ action: "set-memory", memory: null })}
            size="sm"
            type="button"
            variant="outline"
          >
            Remove memory
          </Button>
        ) : null}
      </div>
    </div>
  );
}
