import assert from "node:assert/strict";
import { test } from "node:test";

import {
  approvalDecision,
  buildThreadStatusTags,
  groupThreadTasks,
  isApprovalRequest,
  ownerDecisions,
  parseThreadStatusEvent,
  reduceThreadTasks,
} from "./threadStatus.ts";

const CH = "11111111-1111-4111-8111-111111111111";
const ROOT = "a".repeat(64);
const ASK = "b".repeat(64);

function status(id, value, createdAt, extra = {}) {
  const tags = [
    ["d", extra.root ?? ROOT],
    ["h", extra.channel ?? CH],
    ["e", extra.root ?? ROOT],
    ["status", value],
    ["title", extra.title ?? "Rotate keys"],
  ];
  if (extra.ask) tags.push(["ask", extra.ask, ASK]);
  return {
    id,
    pubkey: extra.pubkey ?? "c".repeat(64),
    created_at: createdAt,
    kind: 30320,
    tags,
    content: "",
    sig: "",
  };
}

test("parseThreadStatusEvent accepts the shared shape and rejects others", () => {
  assert.equal(parseThreadStatusEvent(status("1", "open", 1)).status, "open");
  assert.deepEqual(
    parseThreadStatusEvent(status("2", "awaiting_owner", 1, { ask: "Merge?" }))
      .ask,
    { text: "Merge?", eventId: ASK },
  );
  assert.equal(parseThreadStatusEvent(status("3", "awaiting_owner", 1)), null);
  assert.equal(
    parseThreadStatusEvent(status("4", "blocked", 1, { ask: "Q?" })),
    null,
  );
  assert.equal(parseThreadStatusEvent(status("5", "finished", 1)), null);
  assert.equal(
    parseThreadStatusEvent(status("6", "open", 1, { title: "é".repeat(81) })),
    null,
  );
  assert.equal(
    parseThreadStatusEvent(status("7", "open", 1, { title: "é".repeat(80) }))
      .title.length,
    80,
  );
  assert.equal(
    parseThreadStatusEvent({ ...status("8", "open", 1), content: "x" }),
    null,
  );
});

test("reduceThreadTasks keeps the newest per root across authors", () => {
  const tasks = reduceThreadTasks(
    [
      status("1", "open", 10),
      status("2", "blocked", 20, { pubkey: "d".repeat(64) }),
      status("3", "in_progress", 15),
    ],
    CH,
  );
  assert.equal(tasks.get(ROOT).status, "blocked");
});

test("reduceThreadTasks breaks created_at ties by lower id", () => {
  const tasks = reduceThreadTasks(
    [status("f2", "done", 10), status("a1", "blocked", 10)],
    CH,
  );
  assert.equal(tasks.get(ROOT).eventId, "a1");
});

test("reduceThreadTasks ignores other channels", () => {
  assert.equal(
    reduceThreadTasks([status("1", "open", 1, { channel: "other" })], CH).size,
    0,
  );
});

test("groupThreadTasks puts open with in progress and keeps 20 done", () => {
  const events = [
    status("o", "open", 1, { root: "1".repeat(64) }),
    status("w", "awaiting_owner", 2, { root: "2".repeat(64), ask: "Q?" }),
    status("b", "blocked", 3, { root: "3".repeat(64) }),
  ];
  for (let i = 0; i < 25; i += 1)
    events.push(
      status(`d${i}`, "done", 100 + i, {
        root: i.toString(16).padStart(64, "9"),
      }),
    );
  const groups = groupThreadTasks(reduceThreadTasks(events, CH).values());
  assert.deepEqual(
    [
      groups.needsYou.length,
      groups.inProgress.length,
      groups.blocked.length,
      groups.done.length,
    ],
    [1, 1, 1, 20],
  );
  assert.equal(groups.done[0].eventId, "d24");
});

test("groupThreadTasks moves a decided ask from Needs you to In progress", () => {
  const tasks = [
    ...reduceThreadTasks(
      [
        status("w", "awaiting_owner", 2, { root: "2".repeat(64), ask: "Q?" }),
        status("o", "open", 1, { root: "1".repeat(64) }),
      ],
      CH,
    ).values(),
  ];
  assert.equal(groupThreadTasks(tasks).needsYou.length, 1);
  const groups = groupThreadTasks(tasks, new Map([[ASK, "approve"]]));
  assert.equal(groups.needsYou.length, 0);
  assert.deepEqual(
    groups.inProgress.map((task) => task.eventId),
    ["w", "o"],
  );
});

test("buildThreadStatusTags writes the contract order", () => {
  assert.deepEqual(
    buildThreadStatusTags({
      rootId: ROOT,
      channelId: CH,
      status: "done",
      title: "T",
    }),
    [
      ["d", ROOT],
      ["h", CH],
      ["e", ROOT],
      ["status", "done"],
      ["title", "T"],
    ],
  );
});

test("approval helpers", () => {
  assert.equal(isApprovalRequest([["notification", "approval"]]), true);
  assert.equal(isApprovalRequest([["h", CH]]), false);
  assert.equal(
    approvalDecision([{ emoji: "✅", reactedByCurrentUser: true }]),
    "approve",
  );
  assert.equal(
    approvalDecision([{ emoji: "❌", reactedByCurrentUser: true }]),
    "deny",
  );
  assert.equal(
    approvalDecision([{ emoji: "✅", reactedByCurrentUser: false }]),
    null,
  );
});

test("ownerDecisions keeps the first owner decision per ask", () => {
  const me = "d".repeat(64);
  const ask2 = "c".repeat(64);
  const reaction = (id, pubkey, content, createdAt, target) => ({
    id,
    pubkey,
    created_at: createdAt,
    kind: 7,
    tags: [["e", target]],
    content,
    sig: "",
  });
  const decisions = ownerDecisions(
    [
      reaction("1", "e".repeat(64), "❌", 5, ASK),
      reaction("2", me, "👍", 6, ASK),
      reaction("3", me, "❌", 20, ASK),
      reaction("4", me, "✅", 10, ASK),
      reaction("5", me, "❌", 30, ask2),
    ],
    me.toUpperCase(),
  );
  assert.equal(decisions.get(ASK), "approve");
  assert.equal(decisions.get(ask2), "deny");
  assert.equal(decisions.size, 2);
});
