import * as React from "react";
import { toast } from "sonner";

import { Button } from "@/shared/ui/button";
import {
  APPROVE_EMOJI,
  DENY_EMOJI,
  type OwnerDecision,
  type ThreadTask,
} from "../lib/threadStatus";
import type { ChannelTasksState } from "../useChannelTasks";

const ROW_SETTLE_MS = 500;

const STATUS_LABEL: Record<ThreadTask["status"], string> = {
  open: "Open",
  in_progress: "In progress",
  awaiting_owner: "Needs you",
  blocked: "Blocked",
  done: "Done",
};

function TaskRow({
  task,
  canSetStatus,
  stored,
  settling,
  onMoved,
  onDecided,
  onOpenMessage,
  onReact,
  onDone,
}: {
  task: ThreadTask;
  canSetStatus: boolean;
  stored: OwnerDecision | undefined;
  settling: () => boolean;
  onMoved: () => void;
  onDecided: (askId: string, decision: OwnerDecision) => void;
  onOpenMessage: (messageId: string, rootId: string | null) => void;
  onReact: (eventId: string, emoji: string) => Promise<void>;
  onDone: (task: ThreadTask) => Promise<void>;
}) {
  const [pending, setPending] = React.useState(false);
  const [answered, setAnswered] = React.useState<{
    askId: string;
    value: "approve" | "deny";
  } | null>(null);
  const [error, setError] = React.useState<string | null>(null);
  const run = async (
    action: () => Promise<void>,
    failure: string,
    onDone?: () => void,
  ) => {
    if (settling()) return;
    setPending(true);
    setError(null);
    try {
      await action();
      onDone?.();
    } catch (caught) {
      console.error(failure, caught);
      setError(failure);
      toast.error(failure);
    } finally {
      setPending(false);
    }
  };
  const ask = task.ask;
  const decision =
    stored ?? (ask && answered?.askId === ask.eventId ? answered.value : null);
  return (
    <li
      className="flex items-start gap-3 rounded-lg border border-border/60 px-3 py-2"
      data-status={task.status}
      data-testid="task-row"
    >
      <button
        className="min-w-0 flex-1 rounded-md text-left focus-visible:outline-hidden focus-visible:ring-1 focus-visible:ring-ring"
        data-testid="task-open"
        onClick={() => {
          if (settling()) return;
          if (ask) onOpenMessage(ask.eventId, task.rootId);
          else onOpenMessage(task.rootId, null);
        }}
        type="button"
      >
        <span className="block truncate text-sm font-semibold">
          {task.title}
        </span>
        <span className="block text-xs text-muted-foreground">
          {STATUS_LABEL[stored ? "in_progress" : task.status]}
        </span>
        {ask ? <span className="mt-1 block text-sm">{ask.text}</span> : null}
      </button>
      {ask && decision ? (
        <span
          className="text-sm text-muted-foreground"
          data-testid="task-decision"
        >
          {decision === "approve" ? "Approved" : "Denied"}
        </span>
      ) : null}
      {ask && !decision && canSetStatus ? (
        <>
          <Button
            data-testid="task-approve"
            disabled={pending}
            onClick={() =>
              void run(
                () => onReact(ask.eventId, APPROVE_EMOJI),
                "Couldn't send approval",
                () => {
                  setAnswered({ askId: ask.eventId, value: "approve" });
                  onDecided(ask.eventId, "approve");
                },
              )
            }
            size="sm"
            type="button"
            variant="outline"
          >
            {APPROVE_EMOJI} Approve
          </Button>
          <Button
            data-testid="task-deny"
            disabled={pending}
            onClick={() =>
              void run(
                () => onReact(ask.eventId, DENY_EMOJI),
                "Couldn't send denial",
                () => {
                  setAnswered({ askId: ask.eventId, value: "deny" });
                  onDecided(ask.eventId, "deny");
                },
              )
            }
            size="sm"
            type="button"
            variant="outline"
          >
            {DENY_EMOJI} Deny
          </Button>
        </>
      ) : null}
      {error ? (
        <span className="text-xs text-destructive" data-testid="task-error">
          {error}
        </span>
      ) : null}
      {canSetStatus && task.status !== "done" ? (
        <Button
          data-testid="task-done"
          disabled={pending}
          onClick={() =>
            void run(() => onDone(task), "Couldn't close the task", onMoved)
          }
          size="sm"
          type="button"
          variant="ghost"
        >
          Done
        </Button>
      ) : null}
    </li>
  );
}

export function ChannelTasksTab({
  tasks,
  canSetStatus,
  onOpenMessage,
  onReact,
}: {
  tasks: ChannelTasksState;
  canSetStatus: boolean;
  onOpenMessage: (messageId: string, rootId: string | null) => void;
  onReact: (eventId: string, emoji: string) => Promise<void>;
}) {
  const [showDone, setShowDone] = React.useState(false);
  const movedAt = React.useRef(0);
  const settling = () => Date.now() - movedAt.current < ROW_SETTLE_MS;
  const onMoved = () => {
    movedAt.current = Date.now();
  };
  const onDecided = (askId: string, decision: OwnerDecision) => {
    onMoved();
    tasks.recordDecision(askId, decision);
  };
  const onDone = (task: ThreadTask) => tasks.setStatus(task, "done");
  const section = (id: string, title: string, list: ThreadTask[]) =>
    list.length === 0 ? null : (
      <section className="space-y-2" data-testid={id}>
        <h3 className="text-xs font-semibold uppercase text-muted-foreground">
          {title}
        </h3>
        <ul className="space-y-2">
          {list.map((task) => (
            <TaskRow
              canSetStatus={canSetStatus}
              key={task.rootId}
              onDecided={onDecided}
              onDone={onDone}
              onMoved={onMoved}
              onOpenMessage={onOpenMessage}
              onReact={onReact}
              settling={settling}
              stored={
                task.ask ? tasks.decisions.get(task.ask.eventId) : undefined
              }
              task={task}
            />
          ))}
        </ul>
      </section>
    );
  return (
    <div
      className="mx-auto max-w-3xl space-y-6 py-4"
      data-testid="channel-tasks-tab"
    >
      {section("tasks-group-needs-you", "Needs you", tasks.groups.needsYou)}
      {section(
        "tasks-group-in-progress",
        "In progress",
        tasks.groups.inProgress,
      )}
      {section("tasks-group-blocked", "Blocked", tasks.groups.blocked)}
      {tasks.groups.done.length > 0 ? (
        <section className="space-y-2">
          <button
            className="text-xs font-semibold uppercase text-muted-foreground"
            data-testid="tasks-done-toggle"
            onClick={() => setShowDone((v) => !v)}
            type="button"
          >
            Done ({tasks.groups.done.length})
          </button>
          {showDone ? section("tasks-group-done", "", tasks.groups.done) : null}
        </section>
      ) : null}
    </div>
  );
}
