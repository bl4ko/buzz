import assert from "node:assert/strict";
import test from "node:test";

import {
  buildOlympusUsage,
  formatCompactCount,
  formatShare,
  mergeOlympusUsageEvents,
  modelTokenTotal,
  olympusUsageModelOrder,
  parseOlympusUsage,
  summarizeOlympusUsage,
} from "./olympusUsage.ts";

const OPERATOR = "b".repeat(64);
const OTHER = "c".repeat(64);
const OWNER = "a".repeat(64);
const TRUSTED = new Set([OPERATOR]);

let nextId = 1;
function usageEvent({
  d = "olympus-ops/argus",
  content,
  pubkey = OPERATOR,
  status = "active",
  createdAt = 1_000,
  workspace = "ops",
} = {}) {
  nextId += 1;
  return {
    id: nextId.toString(16).padStart(64, "0"),
    pubkey,
    kind: 30193,
    created_at: createdAt,
    content: typeof content === "string" ? content : JSON.stringify(content),
    tags: [
      ["d", d],
      ["p", OWNER],
      ["p", OPERATOR],
      ...(workspace ? [["workspace", workspace]] : []),
      ["status", status],
    ],
    sig: "0".repeat(128),
  };
}

function agentContent(overrides = {}) {
  return {
    v: 1,
    workspace: "ops",
    namespace: "olympus-ops",
    name: "argus",
    harness: "claude-code",
    at: 1_000,
    windows: {
      "24h": {
        tokens: {
          "claude-opus-5-5": { input: 100, output: 50, cacheRead: 1000 },
          "claude-haiku-5-5": { input: 10, output: 5 },
        },
        turns: 4,
        apiErrors: 1,
        runs: 3,
        failedRuns: 1,
        share: 0.6,
      },
      "7d": {
        tokens: { "claude-opus-5-5": { input: 1000, output: 500 } },
        turns: 20,
        apiErrors: 0,
        runs: 12,
        failedRuns: 0,
        share: 0.5,
      },
    },
    lastRun: { schedule: "daily", at: 990, result: "failed" },
    ...overrides,
  };
}

test("parses an agent usage event from a trusted operator", () => {
  const parsed = parseOlympusUsage(
    usageEvent({ content: agentContent() }),
    TRUSTED,
  );
  assert.equal(parsed?.type, "agent");
  assert.equal(parsed.usage.d, "olympus-ops/argus");
  assert.equal(parsed.usage.windows["24h"].turns, 4);
  assert.equal(parsed.usage.windows["24h"].share, 0.6);
  assert.deepEqual(parsed.usage.lastRun, {
    schedule: "daily",
    at: 990,
    result: "failed",
  });
});

test("refuses untrusted authors, tombstones, wrong versions, and bad shapes", () => {
  const cases = [
    usageEvent({ content: agentContent(), pubkey: OTHER }),
    usageEvent({ content: "", status: "deleted" }),
    usageEvent({ content: agentContent({ v: 2 }) }),
    usageEvent({ content: "{not json" }),
    usageEvent({ content: agentContent(), d: "olympus-ops/other" }),
    usageEvent({ content: agentContent(), workspace: "dev" }),
    usageEvent({ content: agentContent({ name: "" }) }),
    { ...usageEvent({ content: agentContent() }), kind: 30190 },
  ];
  for (const event of cases) {
    assert.equal(parseOlympusUsage(event, TRUSTED), null, event.content);
  }
});

test("drops bad numbers, unknown run results, and out-of-range shares", () => {
  const parsed = parseOlympusUsage(
    usageEvent({
      content: agentContent({
        windows: {
          "24h": {
            tokens: { m: { input: -5, output: "7", cacheRead: 3 }, empty: {} },
            turns: "x",
            share: 1.5,
          },
        },
        lastRun: { schedule: "daily", at: 990, result: "maybe" },
      }),
    }),
    TRUSTED,
  );
  assert.deepEqual(parsed.usage.windows["24h"], {
    tokens: { m: { cacheRead: 3 } },
    turns: 0,
    apiErrors: 0,
    runs: 0,
    failedRuns: 0,
    share: null,
  });
  assert.equal(parsed.usage.windows["7d"], null);
  assert.equal(parsed.usage.lastRun, null);
});

test("parses the Hecate account event and clamps the used ratio", () => {
  const parsed = parseOlympusUsage(
    usageEvent({
      d: "hecate",
      workspace: null,
      content: {
        v: 1,
        at: 1_200,
        accounts: [
          { provider: "claude", credential: "b", window: "7d", usedRatio: 1.4 },
          {
            provider: "claude",
            credential: "a",
            window: "5h",
            usedRatio: 0.25,
          },
          { provider: "claude", credential: "c", window: "5h" },
        ],
      },
    }),
    TRUSTED,
  );
  assert.equal(parsed?.type, "accounts");
  assert.deepEqual(parsed.accounts.accounts, [
    { provider: "claude", credential: "a", window: "5h", usedRatio: 0.25 },
    { provider: "claude", credential: "b", window: "7d", usedRatio: 1 },
  ]);
});

test("a newer tombstone removes the agent; the newest event wins", () => {
  const old = usageEvent({ content: agentContent(), createdAt: 1_000 });
  const newer = usageEvent({
    content: agentContent({ harness: "codex" }),
    createdAt: 1_100,
  });
  const merged = mergeOlympusUsageEvents([old], [newer]);
  assert.equal(merged.length, 1);
  assert.equal(buildOlympusUsage(merged, TRUSTED).agents[0].harness, "codex");

  const tombstone = usageEvent({
    content: "",
    status: "deleted",
    createdAt: 1_200,
  });
  assert.deepEqual(
    buildOlympusUsage([old, newer, tombstone], TRUSTED).agents,
    [],
  );
});

test("model totals skip the Codex subset types and prefer an explicit total", () => {
  assert.equal(
    modelTokenTotal({
      input: 100,
      output: 50,
      cacheRead: 1000,
      cacheCreation: 7,
    }),
    1157,
  );
  assert.equal(
    modelTokenTotal({
      input: 100,
      cached_input: 80,
      output: 50,
      reasoning_output: 20,
    }),
    150,
  );
  assert.equal(modelTokenTotal({ input: 100, output: 50, total: 120 }), 120);
});

test("summarizes a window: rows by tokens, totals, and models", () => {
  const argus = usageEvent({ content: agentContent() });
  const zeus = usageEvent({
    d: "olympus-zeus/zeus",
    workspace: "zeus",
    content: agentContent({
      workspace: "zeus",
      namespace: "olympus-zeus",
      name: "zeus",
      windows: {
        "24h": {
          tokens: { "claude-opus-5-5": { input: 5000, output: 100 } },
          turns: 9,
          apiErrors: 0,
          runs: 1,
          failedRuns: 0,
          share: 0.4,
        },
      },
      lastRun: null,
    }),
  });
  const quiet = usageEvent({
    d: "olympus-dev/proof",
    workspace: "dev",
    content: agentContent({
      workspace: "dev",
      namespace: "olympus-dev",
      name: "proof",
      windows: {},
    }),
  });
  const state = buildOlympusUsage([argus, zeus, quiet], TRUSTED);
  const day = summarizeOlympusUsage(state.agents, "24h");
  assert.deepEqual(
    day.rows.map((row) => [row.usage.name, row.tokens]),
    [
      ["zeus", 5100],
      ["argus", 1165],
      ["proof", 0],
    ],
  );
  assert.deepEqual(day.rows[1].models, [
    { model: "claude-opus-5-5", tokens: 1150 },
    { model: "claude-haiku-5-5", tokens: 15 },
  ]);
  assert.deepEqual(day.total, {
    tokens: 6265,
    turns: 13,
    runs: 4,
    failedRuns: 1,
    apiErrors: 1,
    models: [
      { model: "claude-opus-5-5", tokens: 6250 },
      { model: "claude-haiku-5-5", tokens: 15 },
    ],
  });
  assert.equal(summarizeOlympusUsage(state.agents, "7d").total.tokens, 1500);
  assert.deepEqual(olympusUsageModelOrder(state.agents), [
    "claude-opus-5-5",
    "claude-haiku-5-5",
  ]);
});

test("formats compact counts and shares", () => {
  const table = [
    [0, "0"],
    [999, "999"],
    [1_000, "1k"],
    [1_500, "1.5k"],
    [12_345, "12k"],
    [999_400, "999k"],
    [999_600, "1M"],
    [1_234_567, "1.2M"],
    [45_000_000, "45M"],
    [3_200_000_000, "3.2B"],
  ];
  for (const [value, expected] of table) {
    assert.equal(formatCompactCount(value), expected, String(value));
  }
  assert.equal(formatShare(null), "–");
  assert.equal(formatShare(0), "0%");
  assert.equal(formatShare(0.004), "<1%");
  assert.equal(formatShare(0.456), "46%");
});
