import assert from "node:assert/strict";
import test from "node:test";

import {
  olympusAgentRisks,
  olympusMergePatch,
  olympusSpecPatch,
  olympusWithoutNulls,
} from "./olympusRisk.ts";

test("a spec patch sets changes, clears removed fields, and recurses into objects", () => {
  const before = {
    model: "a",
    effort: "low",
    profile: { displayName: "Z", about: "old" },
    mcpServers: [{ name: "share" }],
    backup: false,
  };
  const after = {
    model: "b",
    profile: { displayName: "Z" },
    mcpServers: [{ name: "share" }, { name: "search" }],
    backup: false,
    storage: "10Gi",
  };
  assert.deepEqual(olympusSpecPatch(before, after), {
    model: "b",
    effort: null,
    profile: { about: null },
    mcpServers: [{ name: "share" }, { name: "search" }],
    storage: "10Gi",
  });
  assert.deepEqual(olympusSpecPatch(before, before), {});
  assert.deepEqual(
    olympusMergePatch(before, olympusSpecPatch(before, after)),
    after,
  );
});

test("nulls are not changes", () => {
  assert.deepEqual(
    olympusSpecPatch({ owner: null, model: "a" }, { model: "a" }),
    {},
  );
  assert.deepEqual(olympusWithoutNulls({ a: null, b: { c: null, d: 1 } }), {
    b: { d: 1 },
  });
});

test("new egress, git write, and new MCP servers are high risk", () => {
  const before = {
    gitSources: [{ name: "agents", access: "read" }],
    mcpServers: [{ name: "share" }],
    egress: [],
  };
  assert.deepEqual(
    olympusAgentRisks(
      before,
      {
        gitSources: [{ name: "agents", access: "write" }],
        mcpServers: [{ name: "share" }, { name: "github" }],
        egress: [{ cidr: "10.0.0.0/8" }],
      },
      { master: false },
    ),
    ["egress direct", "git write", "mcpServers credential"],
  );
});

test("high-risk fields follow the operator list", () => {
  const before = { model: "a", secrets: [], egress: [{ host: "x" }] };
  assert.deepEqual(
    olympusAgentRisks(before, { ...before, model: "b" }, { master: false }),
    [],
  );
  assert.deepEqual(
    olympusAgentRisks(
      before,
      {
        ...before,
        secrets: [{ name: "token" }],
        runtimeClass: "gvisor",
        egress: [{ preset: "internet" }],
      },
      { master: false },
    ),
    ["secrets", "runtimeClass", "egress open"],
  );
  assert.deepEqual(
    olympusAgentRisks(before, { ...before, model: "b" }, { master: true }),
    ["master agent"],
  );
  assert.deepEqual(
    olympusAgentRisks(
      null,
      { kubernetesRole: "reader", role: "master" },
      {
        master: false,
      },
    ),
    ["kubernetesRole", "role"],
  );
});
