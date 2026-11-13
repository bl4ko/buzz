import assert from "node:assert/strict";
import test from "node:test";

import {
  olympusCreateChange,
  olympusCreateSpec,
  olympusPoolsFor,
  olympusStartDraft,
} from "./olympusNewAgent.ts";

const workspace = {
  providers: [
    { name: "claude", models: ["claude-opus-5-5"], protocols: ["anthropic"] },
    { name: "codex", models: ["gpt-5.5"], protocols: ["openai"] },
  ],
  mcpServers: ["share", "hindsight"],
  templates: [],
};

const template = {
  name: "base",
  namespace: "olympus",
  harness: "claude-code",
  pool: "claude",
  model: "claude-opus-5-5",
  effort: "high",
  mcpServers: ["share"],
  memory: { bank: "private" },
};

function agent(rawSpec, extra = {}) {
  return {
    name: "argus",
    rawSpec,
    effectiveSpec: null,
    spec: {
      harness: rawSpec.harness,
      pool: rawSpec.pool,
      model: rawSpec.model,
      effort: rawSpec.effort ?? null,
      instructions: rawSpec.instructions ?? null,
      instructionsFrom: rawSpec.instructionsFrom ?? null,
      mcpServers: rawSpec.mcpServers ?? [],
      memory: rawSpec.memory ?? null,
      egress: rawSpec.egress ?? [],
    },
    ...extra,
  };
}

test("pools are filtered by the harness protocol", () => {
  assert.deepEqual(
    olympusPoolsFor(workspace, "codex").map((pool) => pool.name),
    ["codex"],
  );
  assert.deepEqual(
    olympusPoolsFor(workspace, "claude-code").map((pool) => pool.name),
    ["claude"],
  );
});

test("a blank agent has the full runtime", () => {
  const start = { kind: "blank" };
  const draft = {
    ...olympusStartDraft(start, workspace),
    name: "scout",
    mcpServers: ["share"],
    memory: "workspace",
    displayName: "Scout",
  };
  assert.deepEqual(olympusCreateSpec(start, draft), {
    harness: "claude-code",
    pool: "claude",
    model: "claude-opus-5-5",
    mcpServers: [{ name: "share" }],
    memory: { bank: "workspace" },
    profile: { displayName: "Scout" },
  });
});

test("a template agent keeps only the overrides", () => {
  const start = { kind: "template", template };
  const draft = { ...olympusStartDraft(start, workspace), name: "scout" };
  assert.deepEqual(olympusCreateSpec(start, draft), { template: "base" });
  assert.deepEqual(olympusCreateChange(start, draft, false).risks, [
    "template",
  ]);
  const changed = { ...draft, model: "claude-sonnet-5-5", memory: "" };
  assert.deepEqual(olympusCreateSpec(start, changed), {
    template: "base",
    model: "claude-sonnet-5-5",
    memory: null,
  });
});

test("a clone copies the spec without identity, owner, role, and profile", () => {
  const source = agent({
    harness: "claude-code",
    pool: "claude",
    model: "claude-opus-5-5",
    identityPath: "agents/argus",
    owner: "a".repeat(64),
    role: "master",
    suspend: true,
    profile: { displayName: "Argus" },
    secrets: [{ name: "token" }],
    mcpServers: [{ name: "share", tools: ["upload_file"] }],
    instructionsFrom: { skillsRepo: "agents", path: "argus.md" },
    resources: { limits: { memory: "2Gi" } },
    egress: [{ host: "api.github.com", ports: [443] }],
  });
  const start = { kind: "clone", agent: source };
  const draft = olympusStartDraft(start, workspace);
  assert.equal(draft.name, "argus-copy");
  const { change, risks } = olympusCreateChange(start, draft, false);
  assert.deepEqual(change, {
    action: "create",
    spec: {
      harness: "claude-code",
      pool: "claude",
      model: "claude-opus-5-5",
      secrets: [{ name: "token" }],
      mcpServers: [{ name: "share", tools: ["upload_file"] }],
      instructionsFrom: { skillsRepo: "agents", path: "argus.md" },
      resources: { limits: { memory: "2Gi" } },
      egress: [{ host: "api.github.com", ports: [443] }],
    },
  });
  assert.deepEqual(risks, ["secrets", "mcpServers credential"]);
});

test("open internet egress is a high risk; the old operator gets the old create", () => {
  const start = { kind: "blank" };
  const draft = {
    ...olympusStartDraft(start, workspace),
    name: "web",
    egress: "internet",
    instructions: "Browse.",
  };
  assert.deepEqual(olympusCreateChange(start, draft, false).risks, [
    "egress open",
  ]);
  assert.deepEqual(olympusCreateChange(start, draft, true), {
    change: {
      action: "create",
      harness: "claude-code",
      pool: "claude",
      model: "claude-opus-5-5",
      instructions: "Browse.",
    },
    risks: [],
  });
});
