import assert from "node:assert/strict";
import test from "node:test";

import {
  CHANNEL_AUX_EVENT_KINDS,
  CHANNEL_EVENT_KINDS,
  CHANNEL_MESSAGE_EVENT_KINDS,
  CHANNEL_TIMELINE_CONTENT_KINDS,
  HOME_MENTION_EVENT_KINDS,
  KIND_STREAM_MESSAGE_PINNED,
} from "../../../shared/constants/kinds.ts";
import {
  buildPinEventTags,
  isPinnableMessage,
  mergePinEvent,
  nextPinCreatedAt,
  parsePinEvent,
  reducePinEvents,
  selectPinnedMessages,
  selectPinnedRecords,
} from "./messagePins.ts";

const CHANNEL = "channel-1";

function pinEvent({
  id,
  target = "m1",
  status = "pinned",
  createdAt = 100,
  channel = CHANNEL,
  pubkey = "a".repeat(64),
  tags,
}) {
  return {
    id,
    pubkey,
    created_at: createdAt,
    kind: KIND_STREAM_MESSAGE_PINNED,
    tags: tags ?? [
      ["h", channel],
      ["e", target],
      ["status", status],
    ],
    content: "",
    sig: "",
  };
}

function message(id) {
  return {
    id,
    pubkey: "b".repeat(64),
    created_at: 50,
    kind: 9,
    tags: [["h", CHANNEL]],
    content: `body ${id}`,
    sig: "",
  };
}

function pinnedTargetIds(events) {
  return selectPinnedRecords(reducePinEvents(events, CHANNEL)).map(
    (record) => record.targetId,
  );
}

test("pin kind stays out of timeline, unread, mention, and aux kind lists", () => {
  for (const kinds of [
    CHANNEL_AUX_EVENT_KINDS,
    CHANNEL_EVENT_KINDS,
    CHANNEL_MESSAGE_EVENT_KINDS,
    CHANNEL_TIMELINE_CONTENT_KINDS,
    HOME_MENTION_EVENT_KINDS,
  ]) {
    assert.equal(kinds.includes(KIND_STREAM_MESSAGE_PINNED), false);
  }
  assert.equal(KIND_STREAM_MESSAGE_PINNED, 40004);
});

test("pin state reduction table", () => {
  const cases = [
    {
      name: "single pin",
      events: [pinEvent({ id: "p1" })],
      expected: ["m1"],
    },
    {
      name: "newer unpin wins",
      events: [
        pinEvent({ id: "p1", createdAt: 100 }),
        pinEvent({ id: "p2", createdAt: 101, status: "unpinned" }),
      ],
      expected: [],
    },
    {
      name: "newer unpin wins regardless of arrival order",
      events: [
        pinEvent({ id: "p2", createdAt: 101, status: "unpinned" }),
        pinEvent({ id: "p1", createdAt: 100 }),
      ],
      expected: [],
    },
    {
      name: "re-pin after unpin",
      events: [
        pinEvent({ id: "p1", createdAt: 100 }),
        pinEvent({ id: "p2", createdAt: 101, status: "unpinned" }),
        pinEvent({ id: "p3", createdAt: 102 }),
      ],
      expected: ["m1"],
    },
    {
      name: "tie: lower event id wins (pinned has lower id)",
      events: [
        pinEvent({ id: "bb", createdAt: 100, status: "unpinned" }),
        pinEvent({ id: "aa", createdAt: 100 }),
      ],
      expected: ["m1"],
    },
    {
      name: "tie: lower event id wins (unpinned has lower id)",
      events: [
        pinEvent({ id: "bb", createdAt: 100 }),
        pinEvent({ id: "aa", createdAt: 100, status: "unpinned" }),
      ],
      expected: [],
    },
    {
      name: "other channel ignored",
      events: [pinEvent({ id: "p1", channel: "channel-2" })],
      expected: [],
    },
    {
      name: "invalid status ignored",
      events: [
        pinEvent({ id: "p1", createdAt: 100 }),
        pinEvent({ id: "p2", createdAt: 200, status: "archived" }),
      ],
      expected: ["m1"],
    },
    {
      name: "two e tags ignored",
      events: [
        pinEvent({
          id: "p1",
          tags: [
            ["h", CHANNEL],
            ["e", "m1"],
            ["e", "m2"],
            ["status", "pinned"],
          ],
        }),
      ],
      expected: [],
    },
    {
      name: "two status tags ignored",
      events: [
        pinEvent({
          id: "p1",
          tags: [
            ["h", CHANNEL],
            ["e", "m1"],
            ["status", "pinned"],
            ["status", "unpinned"],
          ],
        }),
      ],
      expected: [],
    },
    {
      name: "missing h tag ignored",
      events: [
        pinEvent({
          id: "p1",
          tags: [
            ["e", "m1"],
            ["status", "pinned"],
          ],
        }),
      ],
      expected: [],
    },
    {
      name: "independent targets",
      events: [
        pinEvent({ id: "p1", target: "m1", createdAt: 100 }),
        pinEvent({ id: "p2", target: "m2", createdAt: 105 }),
        pinEvent({
          id: "p3",
          target: "m1",
          createdAt: 110,
          status: "unpinned",
        }),
      ],
      expected: ["m2"],
    },
  ];
  for (const { name, events, expected } of cases) {
    assert.deepEqual(pinnedTargetIds(events), expected, name);
  }
});

test("wrong kind is not a pin event", () => {
  assert.equal(parsePinEvent({ ...pinEvent({ id: "p1" }), kind: 9 }), null);
});

test("pinned records are ordered newest pin first", () => {
  const events = [
    pinEvent({ id: "p1", target: "m1", createdAt: 100 }),
    pinEvent({ id: "p2", target: "m2", createdAt: 300 }),
    pinEvent({ id: "p3", target: "m3", createdAt: 200 }),
    pinEvent({ id: "p0", target: "m4", createdAt: 300 }),
  ];
  assert.deepEqual(pinnedTargetIds(events), ["m4", "m2", "m3", "m1"]);
});

test("deleted and unloadable targets are excluded", () => {
  const records = selectPinnedRecords(
    reducePinEvents(
      [
        pinEvent({ id: "p1", target: "m1", createdAt: 103 }),
        pinEvent({ id: "p2", target: "m2", createdAt: 102 }),
        pinEvent({ id: "p3", target: "m3", createdAt: 101 }),
      ],
      CHANNEL,
    ),
  );
  const targets = new Map([
    ["m1", message("m1")],
    ["m2", message("m2")],
  ]);
  const visible = selectPinnedMessages(records, targets, new Set(["m2"]));
  assert.deepEqual(
    visible.map((item) => [item.pin.eventId, item.target.id]),
    [["p1", "m1"]],
  );
});

test("pin event tags have the exact protocol shape", () => {
  assert.deepEqual(buildPinEventTags(CHANNEL, "m1", true), [
    ["h", CHANNEL],
    ["e", "m1"],
    ["status", "pinned"],
  ]);
  assert.deepEqual(buildPinEventTags(CHANNEL, "m1", false), [
    ["h", CHANNEL],
    ["e", "m1"],
    ["status", "unpinned"],
  ]);
});

test("next pin timestamp always sorts after the current state", () => {
  const current = parsePinEvent(pinEvent({ id: "p1", createdAt: 500 }));
  assert.equal(nextPinCreatedAt(400, undefined), 400);
  assert.equal(nextPinCreatedAt(400, current), 501);
  assert.equal(nextPinCreatedAt(500, current), 501);
  assert.equal(nextPinCreatedAt(900, current), 900);
});

test("merge dedupes by event id", () => {
  const first = pinEvent({ id: "p1" });
  const merged = mergePinEvent([first], pinEvent({ id: "p1" }));
  assert.equal(merged.length, 1);
  assert.equal(mergePinEvent(merged, pinEvent({ id: "p2" })).length, 2);
});

test("pinnable message table", () => {
  const cases = [
    [{ kind: 9, pending: false }, true],
    [{ kind: 40002 }, true],
    [{ kind: 9, pending: true }, false],
    [{ kind: undefined }, false],
    [{ kind: 40099 }, false],
    [{ kind: 48100 }, false],
    [{ kind: 40008 }, false],
    [{ kind: 43001 }, false],
  ];
  for (const [input, expected] of cases) {
    assert.equal(isPinnableMessage(input), expected, JSON.stringify(input));
  }
});
