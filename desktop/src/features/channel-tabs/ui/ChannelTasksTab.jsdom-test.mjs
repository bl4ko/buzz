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

async function render(canSetStatus = true) {
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
        onReact: async (eventId, emoji) => calls.reacted.push([eventId, emoji]),
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
  await act(async () => q("task-deny").click());
  assert.deepEqual(calls.reacted, [
    [ASK, "✅"],
    [ASK, "❌"],
  ]);
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

test("Done buttons need the owner", async () => {
  await render(false);
  assert.equal(container.querySelector('[data-testid="task-done"]'), null);
});
