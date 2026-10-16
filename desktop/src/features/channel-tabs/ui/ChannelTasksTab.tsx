import * as React from "react";
import { toast } from "sonner";

import { Button } from "@/shared/ui/button";
import {
  APPROVE_EMOJI,
  DENY_EMOJI,
  type ThreadTask,
} from "../lib/threadStatus";
import type { ChannelTasksState } from "../useChannelTasks";

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
  onOpenThread,
  onReact,
  onDone,
}: {
  task: ThreadTask;
  canSetStatus: boolean;
  onOpenThread: (rootId: string) => void;
  onReact: (eventId: string, emoji: string) => Promise<void>;
  onDone: (task: ThreadTask) => Promise<void>;
}) {
  const [pending, setPending] = React.useState(false);
  const run = async (action: () => Promise<void>, failure: string) => {
    setPending(true);
    try {
      await action();
    } catch (error) {
      console.error(failure, error);
      toast.error(failure);
    } finally {
      setPending(false);
    }
  };
  const ask = task.ask;
  return (
    <li
      className="flex items-start gap-3 rounded-lg border border-border/60 px-3 py-2"
      data-status={task.status}
      data-testid="task-row"
    >
      <button
        className="min-w-0 flex-1 text-left"
        data-testid="task-open"
        onClick={() => onOpenThread(task.rootId)}
        type="button"
      >
        <span className="block truncate text-sm font-semibold">
          {task.title}
        </span>
        <span className="block text-xs text-muted-foreground">
          {STATUS_LABEL[task.status]}
        </span>
        {ask ? <span className="mt-1 block text-sm">{ask.text}</span> : null}
      </button>
      {ask ? (
        <>
          <Button
            data-testid="task-approve"
            disabled={pending}
            onClick={() =>
              void run(
                () => onReact(ask.eventId, APPROVE_EMOJI),
                "Couldn't send approval",
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
      {canSetStatus && task.status !== "done" ? (
        <Button
          data-testid="task-done"
          disabled={pending}
          onClick={() =>
            void run(() => onDone(task), "Couldn't close the task")
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
  onOpenThread,
  onReact,
}: {
  tasks: ChannelTasksState;
  canSetStatus: boolean;
  onOpenThread: (rootId: string) => void;
  onReact: (eventId: string, emoji: string) => Promise<void>;
}) {
  const [showDone, setShowDone] = React.useState(false);
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
              onDone={onDone}
              onOpenThread={onOpenThread}
              onReact={onReact}
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
