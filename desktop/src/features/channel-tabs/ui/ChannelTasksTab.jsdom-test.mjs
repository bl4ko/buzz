import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import * as React from "react";
import { act } from "react";
import { createRoot } from "react-dom/client";

import { groupThreadTasks } from "../lib/threadStatus.ts";
import { ChannelTasksTab } from "./ChannelTasksTab.tsx";

const ASK = "b".repeat(64);
const task = (rootId, status, extra = {}) => ({
  rootId,
  channelId: "c",
  status,
  title: `Task ${rootId[0]}`,
  ask: null,
  author: "e".repeat(64),
  createdAt: 10,
  eventId: rootId,
  ...extra,
});
const tasks = [
  task("1".repeat(64), "awaiting_owner", {
    ask: { text: "Merge PR 7?", eventId: ASK },
  }),
  task("2".repeat(64), "in_progress"),
  task("3".repeat(64), "blocked"),
  task("4".repeat(64), "done"),
];

let root;
let container;
let calls;

async function render(canSetStatus = true, onReactOverride = null) {
  calls = { opened: [], reacted: [], status: [] };
  const state = {
    channelId: "c",
    tasks,
    groups: groupThreadTasks(tasks),
    awaitingCount: 1,
    isLoading: false,
    setStatus: async (t, s) => calls.status.push([t.rootId, s]),
  };
  container = document.createElement("div");
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () =>
    root.render(
      React.createElement(ChannelTasksTab, {
        tasks: state,
        canSetStatus,
        onOpenThread: (rootId) => calls.opened.push(rootId),
        onReact:
          onReactOverride ??
          (async (eventId, emoji) => calls.reacted.push([eventId, emoji])),
      }),
    ),
  );
}

afterEach(async () => {
  await act(async () => root.unmount());
  container.remove();
});

const q = (id) => container.querySelector(`[data-testid="${id}"]`);

test("groups, ask, approve, deny, done, and open", async () => {
  await render();
  assert.match(q("tasks-group-needs-you").textContent, /Merge PR 7\?/);
  assert.ok(q("tasks-group-in-progress"));
  assert.ok(q("tasks-group-blocked"));
  assert.equal(
    container.querySelectorAll('[data-testid="task-row"][data-status="done"]')
      .length,
    0,
  );
  await act(async () => q("task-approve").click());
  assert.deepEqual(calls.reacted, [[ASK, "✅"]]);
  assert.equal(q("task-decision").textContent, "Approved");
  await act(async () =>
    container.querySelector('[data-testid="task-done"]').click(),
  );
  assert.deepEqual(calls.status, [["1".repeat(64), "done"]]);
  await act(async () =>
    container.querySelector('[data-testid="task-open"]').click(),
  );
  assert.deepEqual(calls.opened, ["1".repeat(64)]);
  await act(async () => q("tasks-done-toggle").click());
  assert.equal(
    container.querySelectorAll('[data-testid="task-row"][data-status="done"]')
      .length,
    1,
  );
});

test("Done, Approve, and Deny buttons need the owner", async () => {
  await render(false);
  assert.equal(container.querySelector('[data-testid="task-done"]'), null);
  assert.equal(q("task-approve"), null);
  assert.equal(q("task-deny"), null);
  assert.match(q("tasks-group-needs-you").textContent, /Merge PR 7\?/);
});

test("a decision replaces the buttons and a failed publish shows an error", async () => {
  await render();
  await act(async () => q("task-deny").click());
  assert.deepEqual(calls.reacted, [[ASK, "❌"]]);
  assert.equal(q("task-decision").textContent, "Denied");
  assert.equal(q("task-approve"), null);
  assert.equal(q("task-deny"), null);
  await act(async () => root.unmount());
  container.remove();
  await render(true, async () => {
    throw new Error("offline");
  });
  await act(async () => q("task-approve").click());
  assert.match(q("task-error").textContent, /Couldn't send approval/);
  assert.ok(q("task-approve"));
  assert.equal(q("task-decision"), null);
});

test("a new ask on the same case shows the buttons again", async () => {
  await render();
  await act(async () => q("task-approve").click());
  assert.equal(q("task-decision").textContent, "Approved");
  const next = [
    {
      ...tasks[0],
      eventId: "next",
      createdAt: 20,
      ask: { text: "Delete the branch?", eventId: "c".repeat(64) },
    },
    ...tasks.slice(1),
  ];
  await act(async () =>
    root.render(
      React.createElement(ChannelTasksTab, {
        tasks: {
          channelId: "c",
          tasks: next,
          groups: groupThreadTasks(next),
          awaitingCount: 1,
          isLoading: false,
          setStatus: async () => {},
        },
        canSetStatus: true,
        onOpenThread: () => {},
        onReact: async () => {},
      }),
    ),
  );
  assert.equal(q("task-decision"), null);
  assert.ok(q("task-approve"));
  assert.match(q("tasks-group-needs-you").textContent, /Delete the branch\?/);
});
