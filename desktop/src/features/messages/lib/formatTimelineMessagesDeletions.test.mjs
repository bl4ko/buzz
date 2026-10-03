import assert from "node:assert/strict";
import test from "node:test";

import {
  countTopLevelTimelineRows,
  formatTimelineMessages,
} from "./formatTimelineMessages.ts";
import { buildMainTimelineEntries } from "./threadPanel.ts";
import { buildTimelineItems } from "./timelineItems.ts";
import { KIND_SYSTEM_MESSAGE } from "@/shared/constants/kinds";

function event(overrides = {}) {
  return {
    id: "a".repeat(64),
    pubkey: "b".repeat(64),
    kind: 9,
    created_at: 1_700_000_000,
    content: "Gateway shutting down",
    tags: [["h", "channel"]],
    sig: "sig",
    ...overrides,
  };
}

for (const payload of [
  { type: "message_deleted", actor: "author" },
  { type: "message_deleted", actor: "admin", target: "author" },
  {
    type: "message_deleted",
    public_reason: "Spam",
    reason_code: "spam",
    action_id: "action",
  },
]) {
  test(`deletion notice stays hidden after history reload: ${JSON.stringify(payload)}`, () => {
    const events = [
      event({ kind: KIND_SYSTEM_MESSAGE, content: JSON.stringify(payload) }),
    ];
    const messages = formatTimelineMessages(events, null, undefined, null);

    assert.deepEqual(messages, []);
    assert.equal(countTopLevelTimelineRows(events), 0);
    assert.deepEqual(
      buildTimelineItems(buildMainTimelineEntries(messages), null).items,
      [],
    );
  });
}

for (const kind of [5, 9005]) {
  test(`kind ${kind} removes the message without a replacement row`, () => {
    const original = event();
    const events = [
      original,
      event({
        id: "c".repeat(64),
        kind,
        content: "",
        tags: [["e", original.id]],
      }),
      event({
        id: "d".repeat(64),
        kind: KIND_SYSTEM_MESSAGE,
        content: JSON.stringify({ type: "message_deleted", actor: "author" }),
      }),
    ];

    assert.deepEqual(formatTimelineMessages(events, null, undefined, null), []);
    assert.equal(countTopLevelTimelineRows(events), 0);
  });
}

test("other system entries and ordinary message text stay visible", () => {
  for (const content of [
    JSON.stringify({
      type: "member_joined",
      actor: "member",
      target: "member",
    }),
    JSON.stringify({ type: "channel_created", actor: "owner" }),
    "invalid JSON",
    "null",
  ]) {
    const events = [event({ kind: KIND_SYSTEM_MESSAGE, content })];
    assert.equal(
      formatTimelineMessages(events, null, undefined, null).length,
      1,
    );
    assert.equal(countTopLevelTimelineRows(events), 1);
  }

  const events = [
    event({ content: JSON.stringify({ type: "message_deleted" }) }),
  ];
  assert.equal(formatTimelineMessages(events, null, undefined, null).length, 1);
  assert.equal(countTopLevelTimelineRows(events), 1);
});
