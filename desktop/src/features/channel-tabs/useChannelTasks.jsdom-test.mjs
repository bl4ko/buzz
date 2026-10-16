import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { act } from "react";

import { createEventTransport, createHookHarness } from "./hookHarness.mjs";
import { useChannelTasks } from "./useChannelTasks.ts";

const CH = "11111111-1111-4111-8111-111111111111";
const ROOT = "a".repeat(64);
const ROOT2 = "c".repeat(64);
const ASK = "b".repeat(64);

function status(id, root, value, createdAt, ask) {
  const tags = [
    ["d", root],
    ["h", CH],
    ["e", root],
    ["status", value],
    ["title", "Rotate keys"],
  ];
  if (ask) tags.push(["ask", ask, ASK]);
  return {
    id,
    pubkey: "e".repeat(64),
    created_at: createdAt,
    kind: 30320,
    tags,
    content: "",
    sig: "",
  };
}

function tasksTransport(events) {
  const transport = createEventTransport(events);
  transport.fetchTasks = async (channelId) => {
    assert.equal(channelId, CH);
    return transport.events;
  };
  return transport;
}

const h = createHookHarness((transport) => useChannelTasks(CH, transport));
afterEach(() => h.unmount());

test("loads, groups, and counts tasks that need the owner", async () => {
  const transport = tasksTransport([
    status("w", ROOT, "awaiting_owner", 10, "Merge PR 7?"),
    status("b", ROOT2, "blocked", 11),
  ]);
  await h.mount(transport);
  await h.waitFor(() => h.latest?.tasks.length === 2);
  assert.equal(h.latest.awaitingCount, 1);
  assert.equal(h.latest.groups.needsYou[0].ask.eventId, ASK);
  assert.deepEqual(transport.liveFilter.kinds, [30320]);
  assert.deepEqual(transport.liveFilter["#h"], [CH]);
});

test("a live status replaces the older one", async () => {
  const transport = tasksTransport([
    status("w", ROOT, "awaiting_owner", 10, "Merge PR 7?"),
  ]);
  await h.mount(transport);
  await h.waitFor(() => h.latest?.awaitingCount === 1);
  await act(async () => transport.live(status("p", ROOT, "in_progress", 20)));
  await h.waitFor(() => h.latest.awaitingCount === 0);
  assert.equal(h.latest.groups.inProgress[0].eventId, "p");
});

test("setStatus done publishes an owner event that keeps the title and moves forward in time", async () => {
  const transport = tasksTransport([
    status("w", ROOT, "awaiting_owner", 10, "Merge PR 7?"),
  ]);
  await h.mount(transport);
  await h.waitFor(() => h.latest?.tasks.length === 1);
  await act(async () => h.latest.setStatus(h.latest.tasks[0], "done"));
  assert.equal(transport.signed[0].kind, 30320);
  assert.equal(transport.signed[0].content, "");
  assert.equal(transport.signed[0].createdAt, 11);
  assert.deepEqual(transport.signed[0].tags, [
    ["d", ROOT],
    ["h", CH],
    ["e", ROOT],
    ["status", "done"],
    ["title", "Rotate keys"],
  ]);
  assert.equal(transport.published.length, 1);
  await h.waitFor(() => h.latest.groups.done.length === 1);
});

test("a reconnect refetches", async () => {
  const transport = tasksTransport([]);
  await h.mount(transport);
  await h.waitFor(() => h.latest && !h.latest.isLoading);
  transport.events = [status("b", ROOT2, "blocked", 11)];
  await act(async () => transport.reconnect());
  await h.waitFor(() => h.latest.tasks.length === 1);
});

test("owner decisions come from the owner's own reactions on the asks", async () => {
  const me = "d".repeat(64);
  const subscriptions = [];
  const reaction = (id, content, createdAt) => ({
    id,
    pubkey: me,
    created_at: createdAt,
    kind: 7,
    tags: [["e", ASK]],
    content,
    sig: "",
  });
  const transport = tasksTransport([
    status("w", ROOT, "awaiting_owner", 10, "Merge PR 7?"),
  ]);
  transport.reactions = [];
  transport.fetchEvents = async (filter) => {
    transport.fetched.push(filter);
    return transport.reactions;
  };
  transport.subscribeLive = async (filter, onEvent) => {
    subscriptions.push({ filter, onEvent });
    return () => {};
  };
  const owner = createHookHarness((t) => useChannelTasks(CH, t, me));
  try {
    await owner.mount(transport);
    await owner.waitFor(() => owner.latest?.tasks.length === 1);
    await owner.waitFor(() => transport.fetched.length === 1);
    assert.deepEqual(transport.fetched[0].kinds, [7]);
    assert.deepEqual(transport.fetched[0].authors, [me]);
    assert.deepEqual(transport.fetched[0]["#e"], [ASK]);
    assert.deepEqual(transport.fetched[0]["#h"], [CH]);
    assert.equal(owner.latest.decisions.get(ASK), undefined);
    assert.equal(owner.latest.awaitingCount, 1);
    const live = subscriptions.find((s) => s.filter.kinds[0] === 7);
    assert.deepEqual(live.filter["#h"], [CH]);
    await act(async () => live.onEvent(reaction("r1", "❌", 12)));
    await owner.waitFor(() => owner.latest.decisions.get(ASK) === "deny");
    assert.equal(owner.latest.awaitingCount, 0);
    assert.equal(owner.latest.groups.needsYou.length, 1);
    transport.reactions = [reaction("r0", "✅", 11), reaction("r1", "❌", 12)];
    await act(async () => owner.latest.refreshDecisions());
    await owner.waitFor(() => owner.latest.decisions.get(ASK) === "approve");
  } finally {
    await owner.unmount();
  }
});
