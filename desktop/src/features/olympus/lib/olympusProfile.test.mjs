import assert from "node:assert/strict";
import test from "node:test";

import { findOwnedOlympusAgent, olympusLastError } from "./olympusProfile.ts";

const ME = "a".repeat(64);
const KEY = "b".repeat(64);

function group(name, agents) {
  return { key: `op:${name}`, name, author: "op", workspace: null, agents };
}

function agent(name, extra = {}) {
  return { name, publicKey: KEY, owner: ME, createdAt: 1, ...extra };
}

test("finds the agent of this key only for its owner", () => {
  const groups = [group("dev", [agent("proof")])];
  assert.equal(findOwnedOlympusAgent(groups, ME, KEY)?.agent.name, "proof");
  assert.equal(
    findOwnedOlympusAgent(groups, ME, KEY.toUpperCase())?.agent.name,
    "proof",
  );
  assert.equal(findOwnedOlympusAgent(groups, "c".repeat(64), KEY), null);
  assert.equal(findOwnedOlympusAgent(groups, ME, "d".repeat(64)), null);
  assert.equal(findOwnedOlympusAgent(groups, "", KEY), null);
  assert.equal(findOwnedOlympusAgent(groups, ME, null), null);
});

test("takes the newest state when two operators publish one key", () => {
  const groups = [
    group("dev", [agent("old", { createdAt: 5 })]),
    group("ops", [agent("new", { createdAt: 9 })]),
  ];
  const match = findOwnedOlympusAgent(groups, ME, KEY);
  assert.equal(match?.agent.name, "new");
  assert.equal(match?.group.name, "ops");
});

test("the last error is the first false condition", () => {
  assert.equal(olympusLastError([]), null);
  assert.equal(
    olympusLastError([{ type: "Ready", status: "True", reason: "Available" }]),
    null,
  );
  assert.deepEqual(
    olympusLastError([
      { type: "Ready", status: "True", reason: "Available", message: "" },
      { type: "Online", status: "False", reason: "NoHeartbeat", message: "" },
      { type: "Backup", status: "False", reason: "Failed", message: "x" },
    ]),
    { title: "NoHeartbeat", detail: null },
  );
  assert.deepEqual(
    olympusLastError([
      { type: "Online", status: "False", reason: null, message: "pod crash" },
    ]),
    { title: "Online", detail: "pod crash" },
  );
});
