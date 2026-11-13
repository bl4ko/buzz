import assert from "node:assert/strict";
import test from "node:test";

import { listOlympusHistory, mergeOlympusHistory } from "./olympusHistory.ts";

const OPERATOR = "b".repeat(64);
const OWNER = "a".repeat(64);

function result(id, createdAt, tags, content = { reason: "applied" }) {
  return {
    id,
    pubkey: OPERATOR,
    kind: 44311,
    created_at: createdAt,
    content: JSON.stringify({ v: 1, ...content }),
    tags: [["e", "f".repeat(64)], ["p", OWNER], ["p", OPERATOR], ...tags],
    sig: "",
  };
}

test("lists change results newest first, scoped to an agent", () => {
  const first = result("1", 10, [
    ["status", "accepted"],
    ["action", "suspend"],
    ["workspace", "ops"],
    ["agent", "argus"],
  ]);
  const events = mergeOlympusHistory(
    [first],
    [
      result(
        "2",
        20,
        [
          ["status", "refused"],
          ["action", "patch"],
          ["workspace", "ops"],
          ["agent", "argus"],
        ],
        { reason: "managed by gitops: spec.model set in gitops-home" },
      ),
      result("3", 30, [
        ["status", "accepted"],
        ["action", "run-now"],
        ["workspace", "ops"],
        ["schedule", "daily-os-updates"],
      ]),
      {
        ...result("4", 40, [
          ["status", "accepted"],
          ["action", "x"],
        ]),
        pubkey: OWNER,
      },
      { ...first },
    ],
  );
  assert.deepEqual(
    events.map((event) => event.id),
    ["4", "3", "2", "1"],
  );
  const operators = new Set([OPERATOR]);
  const all = listOlympusHistory(events, operators);
  assert.deepEqual(
    all.map((entry) => [entry.id, entry.action, entry.status]),
    [
      ["3", "run-now", "accepted"],
      ["2", "patch", "refused"],
      ["1", "suspend", "accepted"],
    ],
  );
  assert.equal(all[0].schedule, "daily-os-updates");
  const argus = listOlympusHistory(events, operators, {
    workspace: "ops",
    agent: "argus",
  });
  assert.deepEqual(
    argus.map((entry) => entry.reason),
    ["managed by gitops: spec.model set in gitops-home", "applied"],
  );
});
