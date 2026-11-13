import * as React from "react";
import {
  ArrowLeft,
  Copy,
  MessageSquare,
  Pause,
  Pencil,
  Play,
  SearchX,
  Trash2,
  UserRound,
} from "lucide-react";

import { useAppNavigation } from "@/app/navigation/useAppNavigation";
import {
  type OlympusAgent,
  type OlympusWorkspace,
  type OlympusWorkspaceGroup,
  olympusAgentLabel,
} from "@/features/agents/lib/olympusAgents";
import {
  type OlympusChange,
  olympusRequestKey,
  useOlympusRequestState,
} from "@/features/agents/lib/olympusChangeRequests";
import { OlympusRequestStatus } from "@/features/agents/ui/OlympusAgentParts";
import { useOlympusAgents } from "@/features/agents/useOlympusAgents";
import { useOpenDmMutation } from "@/features/channels/hooks";
import { TopChromeInsetHeader } from "@/shared/layout/TopChromeInsetHeader";
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
import { Skeleton } from "@/shared/ui/skeleton";
import { olympusCanDelete, olympusFieldLocked } from "../lib/olympusOwnership";
import { OlympusAgentEditor } from "./OlympusAgentEditor";
import { OlympusAgentSections } from "./OlympusAgentSections";
import { OlympusNewAgentDialog } from "./OlympusNewAgentDialog";
import {
  OlympusAgentAvatar,
  OlympusEmptyState,
  OlympusGitLock,
  OlympusMasterChip,
  OlympusPhase,
} from "./OlympusParts";

export function OlympusAgentPage({
  agentName,
  workspaceName,
}: {
  agentName: string;
  workspaceName: string;
}) {
  const olympus = useOlympusAgents();
  const { goOlympus } = useAppNavigation();
  const group = olympus.groups.find((item) =>
    item.agents.some(
      (agent) => agent.workspace === workspaceName && agent.name === agentName,
    ),
  );
  const agent =
    group?.agents.find(
      (item) => item.workspace === workspaceName && item.name === agentName,
    ) ?? null;

  return (
    <section
      aria-label={agent ? olympusAgentLabel(agent) : agentName}
      className="flex h-full min-h-0 min-w-0 flex-1 flex-col"
      data-testid="olympus-agent-page"
    >
      <TopChromeInsetHeader flush>
        <div className="flex items-center gap-2 px-4 py-3">
          <Button
            onClick={() => void goOlympus()}
            size="sm"
            type="button"
            variant="ghost"
          >
            <ArrowLeft />
            Olympus
          </Button>
          <span aria-hidden className="text-muted-foreground">
            /
          </span>
          <span className="truncate text-sm text-muted-foreground">
            {workspaceName}
          </span>
        </div>
      </TopChromeInsetHeader>
      <div className="min-h-0 flex-1 overflow-y-auto">
        <div className="mx-auto w-full max-w-5xl px-4 py-5">
          {agent && group ? (
            <OlympusAgentBody
              agent={agent}
              workspace={group.workspace}
              group={group}
            />
          ) : olympus.isLoading ? (
            <Skeleton className="h-40 w-full rounded-xl" />
          ) : (
            <OlympusEmptyState
              icon={SearchX}
              testId="olympus-agent-missing"
              title={`No agent ${workspaceName}/${agentName}`}
            >
              <p>
                Hephaestus publishes no state for this agent. It was deleted, or
                this identity is not its owner.
              </p>
            </OlympusEmptyState>
          )}
        </div>
      </div>
    </section>
  );
}

function OlympusAgentBody({
  agent,
  group,
  workspace,
}: {
  agent: OlympusAgent;
  group: OlympusWorkspaceGroup;
  workspace: OlympusWorkspace | null;
}) {
  const olympus = useOlympusAgents();
  const { goChannel, goOlympus, goProfile } = useAppNavigation();
  const openDm = useOpenDmMutation();
  const key = olympusRequestKey(agent.workspace, agent.name);
  const request = useOlympusRequestState(key);
  const pending = request?.phase === "pending";
  const [editing, setEditing] = React.useState(false);
  const [cloning, setCloning] = React.useState(false);
  const [deleting, setDeleting] = React.useState(false);
  const suspendLocked = olympusFieldLocked(agent, "spec.suspend");
  const label = olympusAgentLabel(agent);

  const send = (change: OlympusChange) =>
    olympus.submitChange(
      key,
      { operator: agent.author, workspace: agent.workspace, agent: agent.name },
      change,
    );

  async function message() {
    if (!agent.publicKey) return;
    const dm = await openDm.mutateAsync({ pubkeys: [agent.publicKey] });
    await goChannel(dm.id);
  }

  return (
    <div className="space-y-5">
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div className="flex min-w-0 items-center gap-3">
          <OlympusAgentAvatar agent={agent} />
          <div className="min-w-0 space-y-1">
            <h1 className="flex flex-wrap items-center gap-2 text-xl font-semibold tracking-tight">
              {label}
              {agent.role === "master" ? <OlympusMasterChip /> : null}
              <OlympusPhase phase={agent.phase} />
            </h1>
            <p className="text-sm text-muted-foreground">
              <span className="font-mono">
                {agent.workspace}/{agent.name}
              </span>
              {agent.reason && agent.phase !== "Online"
                ? ` · ${agent.reason}`
                : ""}
              {agent.spec.profile?.about
                ? ` · ${agent.spec.profile.about}`
                : ""}
            </p>
          </div>
        </div>
        <div className="flex flex-wrap items-center gap-1.5">
          <Button
            disabled={!agent.publicKey || openDm.isPending}
            onClick={() => void message()}
            size="sm"
            type="button"
            variant="outline"
          >
            <MessageSquare />
            Message
          </Button>
          <Button
            disabled={!agent.publicKey}
            onClick={() => {
              if (agent.publicKey) void goProfile(agent.publicKey);
            }}
            size="sm"
            type="button"
            variant="ghost"
          >
            <UserRound />
            Profile
          </Button>
          {suspendLocked ? (
            <span className="flex items-center gap-1 px-2 text-xs text-muted-foreground">
              <OlympusGitLock field="Suspend" />
              Suspend in git
            </span>
          ) : (
            <Button
              disabled={pending}
              onClick={() =>
                void send({ action: agent.spec.suspend ? "resume" : "suspend" })
              }
              size="sm"
              type="button"
              variant="outline"
            >
              {agent.spec.suspend ? <Play /> : <Pause />}
              {agent.spec.suspend ? "Resume" : "Suspend"}
            </Button>
          )}
          <Button
            aria-expanded={editing}
            disabled={pending}
            onClick={() => setEditing(true)}
            size="sm"
            type="button"
            variant="outline"
          >
            <Pencil />
            Edit
          </Button>
          <Button
            disabled={!workspace}
            onClick={() => setCloning(true)}
            size="sm"
            type="button"
            variant="ghost"
          >
            <Copy />
            Clone
          </Button>
          {olympusCanDelete(agent) ? (
            <Button
              className="text-destructive hover:text-destructive"
              disabled={pending}
              onClick={() => setDeleting(true)}
              size="sm"
              type="button"
              variant="ghost"
            >
              <Trash2 />
              Delete
            </Button>
          ) : null}
        </div>
      </header>

      <OlympusRequestStatus
        state={request}
        testId="olympus-agent-request-status"
      />

      <OlympusAgentSections
        agent={agent}
        pending={pending}
        send={send}
        workspace={workspace}
      />

      {editing ? (
        <OlympusAgentEditor
          agent={agent}
          onOpenChange={setEditing}
          send={send}
          workspace={workspace}
        />
      ) : null}
      {cloning && workspace ? (
        <OlympusNewAgentDialog
          group={group}
          onOpenChange={setCloning}
          requestKey={`${olympusRequestKey(group.name, null)}#create`}
          source={agent}
        />
      ) : null}
      <AlertDialog onOpenChange={setDeleting} open={deleting}>
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
                onClick={() => {
                  void send({ action: "delete" }).then((state) => {
                    if (state?.phase === "accepted") void goOlympus();
                  });
                }}
                type="button"
                variant="destructive"
              >
                Delete agent
              </Button>
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
