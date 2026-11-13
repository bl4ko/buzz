import * as React from "react";

import {
  OLYMPUS_EFFORTS,
  type OlympusAgent,
  type OlympusWorkspace,
  olympusModelOptions,
} from "@/features/agents/lib/olympusAgents";
import type { OlympusChange } from "@/features/agents/lib/olympusChangeRequests";
import { OlympusAgentEditForm } from "@/features/agents/ui/OlympusAgentChangeControls";
import { Button } from "@/shared/ui/button";
import { Input } from "@/shared/ui/input";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/shared/ui/sheet";
import { Switch } from "@/shared/ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/shared/ui/tabs";
import { Textarea } from "@/shared/ui/textarea";
import { olympusFieldLocked } from "../lib/olympusOwnership";
import {
  olympusAgentRisks,
  olympusMergePatch,
  olympusSpecPatch,
  olympusWithoutNulls,
} from "../lib/olympusRisk";
import { OlympusGitLock, OlympusSelect } from "./OlympusParts";
import { useOlympusRiskGate } from "./OlympusRiskGate";

type Json = Record<string, unknown>;
type Send = (change: OlympusChange) => unknown;

const NEVER_EDITED = ["identityPath"];

export function olympusEditableSpec(agent: OlympusAgent): Json {
  const spec = olympusWithoutNulls(agent.rawSpec);
  for (const key of Object.keys(spec)) {
    if (
      NEVER_EDITED.includes(key) ||
      olympusFieldLocked(agent, `spec.${key}`)
    ) {
      delete spec[key];
    }
  }
  if (agent.instructionsTruncated) delete spec.instructions;
  return spec;
}

export function olympusPatchChange(
  agent: OlympusAgent,
  after: Json,
): { patch: Json; risks: string[]; locked: string[] } {
  const before = olympusEditableSpec(agent);
  const patch = olympusSpecPatch(before, after);
  const locked = Object.keys(after).filter(
    (key) =>
      !(key in before) &&
      (NEVER_EDITED.includes(key) || olympusFieldLocked(agent, `spec.${key}`)),
  );
  const full = olympusWithoutNulls(agent.rawSpec);
  const risks = olympusAgentRisks(full, olympusMergePatch(full, patch), {
    master: agent.role === "master",
  });
  return { patch, risks, locked };
}

function Field({
  children,
  htmlFor,
  label,
  locked,
}: {
  children: React.ReactNode;
  htmlFor: string;
  label: string;
  locked: boolean;
}) {
  return (
    <div className="space-y-1.5">
      <label
        className="flex items-center gap-1.5 text-sm font-medium"
        htmlFor={htmlFor}
      >
        {label}
        {locked ? <OlympusGitLock field={label} /> : null}
      </label>
      {children}
    </div>
  );
}

function text(value: unknown) {
  return typeof value === "string" ? value : "";
}

function OlympusFormEditor({
  agent,
  onDone,
  submit,
  workspace,
}: {
  agent: OlympusAgent;
  onDone: () => void;
  submit: (after: Json) => void;
  workspace: OlympusWorkspace | null;
}) {
  const id = React.useId();
  const base = React.useMemo(() => olympusEditableSpec(agent), [agent]);
  const shown = React.useMemo(
    () => olympusWithoutNulls(agent.rawSpec),
    [agent],
  );
  const profile = (base.profile ?? {}) as Json;
  const shownProfile = (shown.profile ?? {}) as Json;
  const [displayName, setDisplayName] = React.useState(
    text(shownProfile.displayName),
  );
  const [about, setAbout] = React.useState(text(shownProfile.about));
  const [model, setModel] = React.useState(text(shown.model));
  const [effort, setEffort] = React.useState(text(shown.effort));
  const [instructions, setInstructions] = React.useState(
    text(shown.instructions),
  );
  const [storage, setStorage] = React.useState(text(shown.storage));
  const [backup, setBackup] = React.useState(shown.backup === true);
  const locked = (field: string) => olympusFieldLocked(agent, `spec.${field}`);
  const models = olympusModelOptions(workspace, agent.spec.pool);
  const instructionsLocked =
    locked("instructions") ||
    agent.spec.instructionsFrom !== null ||
    agent.instructionsTruncated;

  const after = (() => {
    const next: Json = { ...base };
    const set = (key: string, value: unknown, allowed: boolean) => {
      if (!allowed) return;
      if (value === "" || value === false || value === undefined) {
        delete next[key];
      } else next[key] = value;
    };
    if (!locked("profile")) {
      const nextProfile: Json = { ...profile };
      if (displayName.trim()) nextProfile.displayName = displayName.trim();
      else delete nextProfile.displayName;
      if (about.trim()) nextProfile.about = about.trim();
      else delete nextProfile.about;
      if (Object.keys(nextProfile).length > 0) next.profile = nextProfile;
      else delete next.profile;
    }
    set("model", model.trim(), !locked("model") && Boolean(model.trim()));
    set("effort", effort, !locked("effort"));
    set("instructions", instructions, !instructionsLocked);
    set("storage", storage.trim(), !locked("storage"));
    set("backup", backup, !locked("backup"));
    return next;
  })();
  const changed = Object.keys(olympusSpecPatch(base, after)).length > 0;

  return (
    <form
      aria-label={`Edit ${agent.name}`}
      className="space-y-4"
      data-testid="olympus-agent-editor-form"
      onSubmit={(event) => {
        event.preventDefault();
        if (changed) submit(after);
        else onDone();
      }}
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field
          htmlFor={`${id}-name`}
          label="Display name"
          locked={locked("profile")}
        >
          <Input
            disabled={locked("profile")}
            id={`${id}-name`}
            maxLength={64}
            onChange={(event) => setDisplayName(event.target.value)}
            placeholder={agent.name}
            value={displayName}
          />
        </Field>
        <Field
          htmlFor={`${id}-storage`}
          label="Storage"
          locked={locked("storage")}
        >
          <Input
            disabled={locked("storage")}
            id={`${id}-storage`}
            onChange={(event) => setStorage(event.target.value)}
            placeholder="5Gi"
            value={storage}
          />
        </Field>
      </div>
      <Field htmlFor={`${id}-about`} label="About" locked={locked("profile")}>
        <Input
          disabled={locked("profile")}
          id={`${id}-about`}
          maxLength={1024}
          onChange={(event) => setAbout(event.target.value)}
          value={about}
        />
      </Field>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field htmlFor={`${id}-model`} label="Model" locked={locked("model")}>
          {models.length > 0 ? (
            <OlympusSelect
              disabled={locked("model")}
              id={`${id}-model`}
              label="Model"
              onChange={setModel}
              options={(models.includes(model) || !model
                ? models
                : [model, ...models]
              ).map((item) => ({ value: item, label: item }))}
              value={model}
            />
          ) : (
            <Input
              disabled={locked("model")}
              id={`${id}-model`}
              onChange={(event) => setModel(event.target.value)}
              value={model}
            />
          )}
        </Field>
        <Field
          htmlFor={`${id}-effort`}
          label="Effort"
          locked={locked("effort")}
        >
          <OlympusSelect
            disabled={locked("effort")}
            id={`${id}-effort`}
            label="Effort"
            onChange={setEffort}
            options={[
              { value: "", label: "Default" },
              ...OLYMPUS_EFFORTS.map((item) => ({ value: item, label: item })),
            ]}
            value={effort}
          />
        </Field>
      </div>
      <Field
        htmlFor={`${id}-instructions`}
        label="Instructions"
        locked={locked("instructions") || locked("instructionsFrom")}
      >
        <Textarea
          className="min-h-48 font-mono text-xs"
          disabled={instructionsLocked}
          id={`${id}-instructions`}
          onChange={(event) => setInstructions(event.target.value)}
          placeholder={
            agent.spec.instructionsFrom
              ? `${agent.spec.instructionsFrom.skillsRepo}/${agent.spec.instructionsFrom.path}`
              : undefined
          }
          value={instructions}
        />
        {agent.spec.instructionsFrom ? (
          <p className="text-xs text-muted-foreground">
            The instructions come from a skills repository.
          </p>
        ) : null}
      </Field>
      <label
        className="flex items-center justify-between gap-3 rounded-lg border border-border/60 px-3 py-2.5 text-sm"
        htmlFor={`${id}-backup`}
      >
        <span className="flex items-center gap-1.5">
          Back up the agent volume
          {locked("backup") ? <OlympusGitLock field="Backup" /> : null}
        </span>
        <Switch
          checked={backup}
          disabled={locked("backup")}
          id={`${id}-backup`}
          onCheckedChange={setBackup}
        />
      </label>
      <div className="flex justify-end gap-2 pt-2">
        <Button onClick={onDone} type="button" variant="outline">
          Cancel
        </Button>
        <Button disabled={!changed} type="submit">
          Save changes
        </Button>
      </div>
    </form>
  );
}

function OlympusJsonEditor({
  agent,
  onDone,
  submit,
}: {
  agent: OlympusAgent;
  onDone: () => void;
  submit: (after: Json) => void;
}) {
  const id = React.useId();
  const initial = React.useMemo(
    () => JSON.stringify(olympusEditableSpec(agent), null, 2),
    [agent],
  );
  const [value, setValue] = React.useState(initial);
  const [error, setError] = React.useState<string | null>(null);
  const locked = (agent.gitopsFields ?? [])
    .filter((field) => field.split(".").length === 2)
    .map((field) => field.slice("spec.".length));
  return (
    <form
      className="space-y-3"
      onSubmit={(event) => {
        event.preventDefault();
        let parsed: unknown;
        try {
          parsed = JSON.parse(value);
        } catch {
          setError("The text is not valid JSON.");
          return;
        }
        if (
          typeof parsed !== "object" ||
          parsed === null ||
          Array.isArray(parsed)
        ) {
          setError("The spec must be a JSON object.");
          return;
        }
        const result = olympusPatchChange(agent, parsed as Json);
        if (result.locked.length > 0) {
          setError(
            `These fields are set in gitops-home: ${result.locked.join(", ")}.`,
          );
          return;
        }
        if (Object.keys(result.patch).length > 0) submit(parsed as Json);
        else onDone();
      }}
    >
      <label className="text-sm font-medium" htmlFor={id}>
        Spec fields that Olympus manages
      </label>
      <Textarea
        aria-describedby={`${id}-help`}
        className="min-h-80 font-mono text-xs"
        id={id}
        onChange={(event) => {
          setValue(event.target.value);
          setError(null);
        }}
        spellCheck={false}
        value={value}
      />
      <p className="text-xs text-muted-foreground" id={`${id}-help`}>
        Remove a field to clear it.{" "}
        {locked.length > 0
          ? `Set in gitops-home, not shown: ${locked.join(", ")}.`
          : "Git sets no field of this agent."}
      </p>
      {error ? (
        <p className="text-sm text-destructive" role="alert">
          {error}
        </p>
      ) : null}
      <div className="flex justify-end gap-2">
        <Button onClick={onDone} type="button" variant="outline">
          Cancel
        </Button>
        <Button disabled={value === initial} type="submit">
          Save spec
        </Button>
      </div>
    </form>
  );
}

export function OlympusAgentEditor({
  agent,
  onOpenChange,
  send,
  workspace,
}: {
  agent: OlympusAgent;
  onOpenChange: (open: boolean) => void;
  send: Send;
  workspace: OlympusWorkspace | null;
}) {
  const gate = useOlympusRiskGate();
  const legacy = agent.gitopsFields === null;
  const done = () => onOpenChange(false);
  const submit = (after: Json) => {
    const { patch, risks } = olympusPatchChange(agent, after);
    if (Object.keys(patch).length === 0) return done();
    gate.guard(agent.name, risks, (confirmed) => {
      void send({
        action: "patch",
        patch,
        ...(confirmed ? { highRisk: true as const } : {}),
      });
      done();
    });
  };
  return (
    <>
      <Sheet onOpenChange={onOpenChange} open>
        <SheetContent
          className="flex w-full flex-col gap-0 overflow-hidden p-0 sm:max-w-xl"
          data-testid="olympus-agent-editor"
        >
          <SheetHeader className="border-b border-border/60 px-6 py-4">
            <SheetTitle>Edit {agent.name}</SheetTitle>
            <SheetDescription>
              {legacy
                ? "This Hephaestus version changes only model, effort, and instructions."
                : "Fields with a lock are set in gitops-home. Change them there."}
            </SheetDescription>
          </SheetHeader>
          <div className="min-h-0 flex-1 overflow-y-auto px-6 py-5">
            {legacy ? (
              agent.managedBy === "gitops" ? (
                <p className="text-sm text-muted-foreground">
                  This agent is in gitops-home. Update Hephaestus to change the
                  fields that git does not set.
                </p>
              ) : (
                <OlympusAgentEditForm
                  agent={agent}
                  disabled={false}
                  onCancel={done}
                  send={(change) => void send(change)}
                  workspace={workspace}
                />
              )
            ) : (
              <Tabs defaultValue="form">
                <TabsList className="mb-4">
                  <TabsTrigger value="form">Settings</TabsTrigger>
                  <TabsTrigger value="json">Spec JSON</TabsTrigger>
                </TabsList>
                <TabsContent value="form">
                  <OlympusFormEditor
                    agent={agent}
                    onDone={done}
                    submit={submit}
                    workspace={workspace}
                  />
                </TabsContent>
                <TabsContent value="json">
                  <OlympusJsonEditor
                    agent={agent}
                    onDone={done}
                    submit={submit}
                  />
                </TabsContent>
              </Tabs>
            )}
          </div>
        </SheetContent>
      </Sheet>
      {gate.dialog}
    </>
  );
}
