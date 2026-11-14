import * as React from "react";
import { useQueryClient } from "@tanstack/react-query";
import { GitCommitHorizontal, TriangleAlert } from "lucide-react";
import { toast } from "sonner";

import type {
  OlympusAgent,
  OlympusInstructionsFile,
} from "@/features/agents/lib/olympusAgents";
import { olympusFileRequestKey } from "@/features/agents/lib/olympusChangeRequests";
import { olympusLineDiff } from "@/features/agents/lib/olympusProposals";
import { useOlympusAgents } from "@/features/agents/useOlympusAgents";
import { cn } from "@/shared/lib/cn";
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
import { Spinner } from "@/shared/ui/spinner";
import {
  type OlympusFileVersion,
  olympusInstructionsFileQueryKey,
  readOlympusInstructionsFile,
} from "../lib/olympusInstructionsFile";

export type OlympusFileReview = {
  file: OlympusInstructionsFile;
  version: OlympusFileVersion;
  draft: string;
  spec: Record<string, unknown> | null;
};

const LINE_STYLES = {
  same: { marker: " ", className: "text-muted-foreground" },
  del: { marker: "-", className: "bg-destructive/10 text-destructive" },
  add: {
    marker: "+",
    className: "bg-emerald-500/10 text-emerald-700 dark:text-emerald-300",
  },
} as const;

export function OlympusFileDiff({
  after,
  before,
  label,
}: {
  after: string;
  before: string;
  label: string;
}) {
  const lines = React.useMemo(
    () => olympusLineDiff(before, after),
    [before, after],
  );
  const added = lines.filter((line) => line.type === "add").length;
  const removed = lines.filter((line) => line.type === "del").length;
  return (
    <div
      className="overflow-hidden rounded-lg border border-border/60 bg-background/60 font-mono text-xs"
      data-testid="olympus-file-diff"
    >
      <div className="flex items-center justify-between gap-2 border-b border-border/60 bg-muted/40 px-3 py-1.5">
        <span className="truncate text-foreground">{label}</span>
        <span className="shrink-0 text-2xs text-muted-foreground">
          <span className="text-emerald-700 dark:text-emerald-300">
            +{added}
          </span>{" "}
          <span className="text-destructive">-{removed}</span>
        </span>
      </div>
      <div className="max-h-80 overflow-auto py-1">
        {lines.map((line, index) => {
          const style = LINE_STYLES[line.type];
          return (
            <div
              className={cn("flex px-1", style.className)}
              data-line={line.type}
              // biome-ignore lint/suspicious/noArrayIndexKey: lines are positional
              key={index}
            >
              <span
                aria-hidden
                className="w-5 shrink-0 select-none text-center opacity-70"
              >
                {style.marker}
              </span>
              <span className="sr-only">
                {line.type === "add"
                  ? "added: "
                  : line.type === "del"
                    ? "removed: "
                    : ""}
              </span>
              <span className="min-w-0 flex-1 whitespace-pre-wrap break-words pr-2">
                {line.text || " "}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

type Stage =
  | { kind: "review" }
  | { kind: "sending" }
  | { kind: "error"; message: string }
  | { kind: "conflict"; theirs: OlympusFileVersion };

export function OlympusInstructionsReview({
  agent,
  onClose,
  onCommitted,
  onUseGitVersion,
  review,
  saveSpec,
}: {
  agent: OlympusAgent;
  onClose: () => void;
  onCommitted: () => void;
  onUseGitVersion: (version: OlympusFileVersion) => void;
  review: OlympusFileReview;
  saveSpec: (spec: Record<string, unknown>) => void;
}) {
  const olympus = useOlympusAgents();
  const queryClient = useQueryClient();
  const [version, setVersion] = React.useState(review.version);
  const [stage, setStage] = React.useState<Stage>({ kind: "review" });
  const [message, setMessage] = React.useState("");
  const specSaved = React.useRef(false);
  const { file, draft } = review;
  const sending = stage.kind === "sending";

  const commit = async () => {
    if (review.spec && !specSaved.current) {
      specSaved.current = true;
      saveSpec(review.spec);
    }
    setStage({ kind: "sending" });
    const state = await olympus.submitChange(
      olympusFileRequestKey(agent.workspace, file.repo, file.path),
      { operator: agent.author, workspace: agent.workspace, agent: null },
      {
        action: "edit-file",
        repo: file.repo,
        path: file.path,
        content: draft,
        base: version.base,
        ...(message.trim() ? { message: message.trim() } : {}),
      },
    );
    if (state === null) {
      setStage({ kind: "error", message: "An edit of this file is running." });
      return;
    }
    if (state.phase === "accepted") {
      const short = (state.commit ?? "").slice(0, 7);
      toast.success(
        state.reason === "unchanged"
          ? "The file already has this text."
          : `Instructions committed${short ? ` (${short})` : ""}. ${agent.name} restarts with the new text.`,
      );
      void queryClient.invalidateQueries({
        queryKey: olympusInstructionsFileQueryKey(file),
      });
      onCommitted();
      return;
    }
    if (state.phase === "refused" && state.reason === "the file changed") {
      try {
        const theirs = await queryClient.fetchQuery({
          queryKey: olympusInstructionsFileQueryKey(file),
          queryFn: () => readOlympusInstructionsFile(file),
          staleTime: 0,
        });
        setStage({ kind: "conflict", theirs });
      } catch (error) {
        setStage({
          kind: "error",
          message: `The file changed in git, and reading it again failed: ${error instanceof Error ? error.message : String(error)}`,
        });
      }
      return;
    }
    setStage({
      kind: "error",
      message:
        state.phase === "failed"
          ? state.reason
          : state.phase === "refused"
            ? `Hephaestus refused the edit: ${state.reason ?? "no reason"}.`
            : "No answer from Hephaestus.",
    });
  };

  return (
    <Dialog
      onOpenChange={(open) => {
        if (!open && !sending) onClose();
      }}
      open
    >
      <DialogContent
        className="flex max-h-[85vh] max-w-2xl flex-col gap-4"
        data-testid="olympus-instructions-review"
      >
        <DialogHeader>
          <DialogTitle>
            {stage.kind === "conflict"
              ? "The file changed in git"
              : "Review the instructions change"}
          </DialogTitle>
          <DialogDescription>
            {stage.kind === "conflict" ? (
              <>
                Someone committed to {file.path} after you opened it (now{" "}
                <span className="font-mono">
                  {stage.theirs.base.slice(0, 7)}
                </span>
                ). Compare the git version with your text.
              </>
            ) : (
              <>
                Olympus commits {file.path} to {file.repo} on {file.branch} as
                olympus-author. The agent restarts with the new text.
              </>
            )}
          </DialogDescription>
        </DialogHeader>
        <div className="min-h-0 flex-1 space-y-3 overflow-y-auto">
          {stage.kind === "conflict" ? (
            <OlympusFileDiff
              after={draft}
              before={stage.theirs.content}
              label={`git ${stage.theirs.base.slice(0, 7)} → your text`}
            />
          ) : (
            <OlympusFileDiff
              after={draft}
              before={version.content}
              label={`${file.path} · ${version.base.slice(0, 7)} → your text`}
            />
          )}
          {stage.kind !== "conflict" ? (
            <div className="space-y-1.5">
              <label
                className="text-sm font-medium"
                htmlFor="olympus-commit-message"
              >
                Commit message
              </label>
              <Input
                disabled={sending}
                id="olympus-commit-message"
                maxLength={200}
                onChange={(event) =>
                  setMessage(event.target.value.replace(/\n/g, " "))
                }
                placeholder={`docs: edit ${file.path} in the Olympus app`}
                value={message}
              />
            </div>
          ) : null}
          {review.spec && stage.kind === "review" ? (
            <p className="text-xs text-muted-foreground">
              The other changed settings are saved too.
            </p>
          ) : null}
          {stage.kind === "error" ? (
            <p
              className="flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive"
              role="alert"
            >
              <TriangleAlert aria-hidden className="mt-0.5 h-4 w-4 shrink-0" />
              {stage.message}
            </p>
          ) : null}
        </div>
        <DialogFooter>
          {stage.kind === "conflict" ? (
            <>
              <Button
                onClick={() => onUseGitVersion(stage.theirs)}
                type="button"
                variant="outline"
              >
                Use the git version
              </Button>
              <Button
                onClick={() => {
                  setVersion(stage.theirs);
                  setStage({ kind: "review" });
                }}
                type="button"
              >
                Keep my text
              </Button>
            </>
          ) : (
            <>
              <Button
                disabled={sending}
                onClick={onClose}
                type="button"
                variant="outline"
              >
                Cancel
              </Button>
              <Button
                data-testid="olympus-instructions-commit"
                disabled={sending}
                onClick={() => void commit()}
                type="button"
              >
                {sending ? (
                  <>
                    <Spinner aria-hidden className="h-4 w-4" />
                    Committing…
                  </>
                ) : (
                  <>
                    <GitCommitHorizontal aria-hidden />
                    Commit change
                  </>
                )}
              </Button>
            </>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
