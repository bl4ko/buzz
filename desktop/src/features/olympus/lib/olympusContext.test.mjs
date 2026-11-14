import assert from "node:assert/strict";
import test from "node:test";

import {
  latestOlympusContexts,
  olympusContextPercent,
  parseOlympusContext,
} from "./olympusContext.ts";

function payload(sessionId, timestamp, context, channelId = "dm") {
  return {
    harness: "claude-agent-acp",
    sessionId,
    channelId,
    timestamp,
    context,
  };
}

const CONTEXT = {
  used: 84312,
  size: 200000,
  turns: 7,
  startedAt: 1794500000,
  compactions: 1,
};

test("reads the context of a turn metric", () => {
  const entry = parseOlympusContext(
    payload("s1", "2026-11-14T16:00:00.000Z", CONTEXT),
  );
  assert.deepEqual(entry, {
    sessionId: "s1",
    channelId: "dm",
    at: Date.parse("2026-11-14T16:00:00.000Z") / 1000,
    used: 84312,
    size: 200000,
    turns: 7,
    startedAt: 1794500000,
    compactions: 1,
  });
  assert.equal(olympusContextPercent(entry), 42);
});

test("skips a metric without context or session", () => {
  assert.equal(
    parseOlympusContext(payload("s1", "2026-11-14T16:00:00Z", undefined)),
    null,
  );
  assert.equal(
    parseOlympusContext({
      timestamp: "2026-11-14T16:00:00Z",
      context: CONTEXT,
    }),
    null,
  );
  assert.equal(parseOlympusContext(null), null);
  const unknown = parseOlympusContext(
    payload("s1", "2026-11-14T16:00:00Z", {
      used: null,
      size: 0,
      turns: 1,
      startedAt: 1,
      compactions: 0,
    }),
  );
  assert.equal(unknown.size, null);
  assert.equal(olympusContextPercent(unknown), null);
});

test("keeps the newest entry of each session, newest session first", () => {
  const entries = [
    parseOlympusContext(
      payload("a", "2026-11-14T10:00:00Z", { ...CONTEXT, turns: 1 }),
    ),
    parseOlympusContext(
      payload("a", "2026-11-14T11:00:00Z", { ...CONTEXT, turns: 2 }),
    ),
    parseOlympusContext(payload("b", "2026-11-14T12:00:00Z", CONTEXT, "other")),
  ];
  assert.deepEqual(
    latestOlympusContexts(entries).map((e) => [e.sessionId, e.turns]),
    [
      ["b", 7],
      ["a", 2],
    ],
  );
  assert.deepEqual(
    latestOlympusContexts(entries, "dm").map((e) => e.sessionId),
    ["a"],
  );
});
