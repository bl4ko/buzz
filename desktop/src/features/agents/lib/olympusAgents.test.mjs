import assert from "node:assert/strict";
import test from "node:test";

import {
  groupOlympusAgents,
  mergeOlympusEvents,
  olympusAddableMcpServers,
  olympusModelOptions,
  parseOlympusAgent,
  parseOlympusWorkspace,
} from "./olympusAgents.ts";

const OPERATOR = "b".repeat(64);
const OTHER_OPERATOR = "c".repeat(64);
const OWNER = "a".repeat(64);
const AGENT_KEY = "d".repeat(64);

function agentContent(overrides = {}) {
  return {
    v: 1,
    workspace: "dev",
    namespace: "olympus-dev",
    name: "proof",
    owner: OWNER,
    managedBy: null,
    spec: {
      harness: "claude-code",
      model: "claude-haiku-5-5",
      pool: "anthropic",
      effort: "high",
      instructions: "Line one\nLine two",
      mcpServers: [{ name: "share", tools: ["upload_file"] }, { name: 7 }],
      services: ["git"],
      memory: { bank: "private" },
      gitSources: [{ name: "repo", access: "write" }],
      skills: [{ repo: "skills", name: "buzz" }],
      egress: [{ host: "example.com", ports: [443, "x"] }],
      suspend: false,
    },
    schedules: [
      {
        name: "ping",
        cron: "*/5 * * * *",
        timeZone: "Europe/Ljubljana",
        prompt: "Say hi",
        script: { inline: "echo hi" },
        lastRunTime: "2026-11-12T10:00:00Z",
        lastResult: "Succeeded",
      },
    ],
    status: {
      phase: "Online",
      reason: null,
      publicKey: AGENT_KEY,
      lastActivity: "2026-11-12T10:00:00Z",
      conditions: [
        { type: "Ready", status: "True", reason: "Available", message: "" },
        { status: "True" },
      ],
    },
    ...overrides,
  };
}

function stateEvent({
  kind = 30190,
  id,
  d = "olympus-dev/proof",
  createdAt = 100,
  status = "active",
  pubkey = OPERATOR,
  content = agentContent(),
  workspace = "dev",
}) {
  return {
    id,
    pubkey,
    kind,
    created_at: createdAt,
    content:
      status === "deleted"
        ? ""
        : typeof content === "string"
          ? content
          : JSON.stringify(content),
    tags: [
      ["d", d],
      ["p", OWNER],
      ["p", OPERATOR],
      ...(kind === 30190 ? [["workspace", workspace]] : []),
      ["status", status],
    ],
    sig: "",
  };
}

function workspaceEvent(overrides = {}) {
  return stateEvent({
    kind: 30191,
    id: "w1",
    d: "dev",
    content: {
      v: 1,
      name: "dev",
      namespace: "olympus-dev",
      owner: OWNER,
      managedBy: null,
      spec: { suspend: false, quota: null },
      status: { phase: "Ready", reason: null, conditions: [] },
      providers: [
        { name: "anthropic", models: ["claude-haiku-5-5"], protocols: [] },
        { name: "local", models: [] },
      ],
      mcpServers: ["share", "hindsight", "search"],
    },
    ...overrides,
  });
}

test("parses a full agent event and drops invalid nested items", () => {
  const agent = parseOlympusAgent(stateEvent({ id: "e1" }));
  assert.ok(agent);
  assert.equal(agent.name, "proof");
  assert.equal(agent.d, "olympus-dev/proof");
  assert.equal(agent.phase, "Online");
  assert.equal(agent.publicKey, AGENT_KEY);
  assert.deepEqual(agent.spec.mcpServers, [
    { name: "share", tools: ["upload_file"] },
  ]);
  assert.deepEqual(agent.spec.memory, { bank: "private" });
  assert.deepEqual(agent.spec.egress[0].ports, [443]);
  assert.equal(agent.schedules[0].script, "echo hi");
  assert.equal(agent.conditions.length, 1);
});

test("reads the role and the agent profile", () => {
  const plain = parseOlympusAgent(stateEvent({ id: "e1" }));
  assert.equal(plain.role, null);
  assert.equal(plain.spec.profile, null);
  const content = agentContent({ role: "master" });
  content.spec.profile = { displayName: "Zeus", picture: "https://p/z.png" };
  const master = parseOlympusAgent(stateEvent({ id: "e2", content }));
  assert.equal(master.role, "master");
  assert.deepEqual(master.spec.profile, {
    displayName: "Zeus",
    picture: "https://p/z.png",
  });
});

test("reads the truncation flags", () => {
  const plain = parseOlympusAgent(stateEvent({ id: "e1" }));
  assert.equal(plain.instructionsTruncated, false);
  assert.equal(plain.schedules[0].truncated, false);
  const content = agentContent({ instructionsTruncated: true });
  content.schedules[0].truncated = true;
  const cut = parseOlympusAgent(stateEvent({ id: "e2", content }));
  assert.equal(cut.instructionsTruncated, true);
  assert.equal(cut.schedules[0].truncated, true);
});

test("ignores invalid agent content", () => {
  const invalid = [
    "not json",
    JSON.stringify([]),
    JSON.stringify(agentContent({ v: 2 })),
    JSON.stringify(agentContent({ name: "" })),
    JSON.stringify(agentContent({ spec: { harness: "codex" } })),
    JSON.stringify(agentContent({ status: { phase: "Exploded" } })),
    JSON.stringify(agentContent({ status: null })),
  ];
  for (const content of invalid) {
    assert.equal(
      parseOlympusAgent(stateEvent({ id: "x", content })),
      null,
      content,
    );
  }
});

test("rejects events with a bad d or status tag", () => {
  const noD = stateEvent({ id: "x" });
  noD.tags = noD.tags.filter((tag) => tag[0] !== "d");
  const twoStatus = stateEvent({ id: "y" });
  twoStatus.tags.push(["status", "active"]);
  assert.equal(parseOlympusAgent(noD), null);
  assert.equal(parseOlympusAgent(twoStatus), null);
  assert.deepEqual(mergeOlympusEvents([], [noD, twoStatus]), []);
});

test("keeps the newest event per kind, author, and d", () => {
  const older = stateEvent({ id: "e1", createdAt: 100 });
  const newer = stateEvent({
    id: "e2",
    createdAt: 200,
    content: agentContent({ status: { phase: "Suspended", reason: "Paused" } }),
  });
  const otherAuthor = stateEvent({
    id: "e3",
    createdAt: 50,
    pubkey: OTHER_OPERATOR,
  });
  const merged = mergeOlympusEvents([newer], [older, otherAuthor]);
  assert.deepEqual(merged.map((event) => event.id).sort(), ["e2", "e3"]);
  const groups = groupOlympusAgents(merged);
  const own = groups.find((group) => group.author === OPERATOR);
  assert.equal(own.agents[0].phase, "Suspended");
  assert.equal(own.agents[0].reason, "Paused");
});

test("breaks created_at ties by the lowest id", () => {
  const a = stateEvent({ id: "aa", createdAt: 100 });
  const b = stateEvent({ id: "bb", createdAt: 100 });
  assert.deepEqual(
    mergeOlympusEvents([b], [a]).map((event) => event.id),
    ["aa"],
  );
  assert.deepEqual(
    mergeOlympusEvents([a], [b]).map((event) => event.id),
    ["aa"],
  );
});

test("a newer tombstone hides the agent and an older active cannot return", () => {
  const active = stateEvent({ id: "e1", createdAt: 100 });
  const tombstone = stateEvent({ id: "e2", createdAt: 200, status: "deleted" });
  const merged = mergeOlympusEvents([tombstone], [active]);
  assert.deepEqual(
    merged.map((event) => event.id),
    ["e2"],
  );
  assert.deepEqual(groupOlympusAgents(merged), []);
  assert.equal(parseOlympusAgent(tombstone), null);
});

test("groups agents by workspace with the workspace state", () => {
  const groups = groupOlympusAgents([
    workspaceEvent(),
    stateEvent({ id: "e1" }),
    stateEvent({
      id: "e2",
      d: "olympus-dev/codex2",
      content: agentContent({
        name: "codex2",
        spec: { harness: "codex", model: "gpt-5", pool: "openai" },
        status: { phase: "Suspended", reason: "Suspended" },
      }),
    }),
    stateEvent({
      id: "e3",
      d: "olympus-ops/argus",
      workspace: "ops",
      content: agentContent({ name: "argus", workspace: "ops" }),
    }),
  ]);
  assert.deepEqual(
    groups.map((group) => [group.name, group.workspace?.phase ?? null]),
    [
      ["dev", "Ready"],
      ["ops", null],
    ],
  );
  assert.deepEqual(
    groups[0].agents.map((agent) => agent.name),
    ["codex2", "proof"],
  );
});

test("a workspace without agents still forms a group", () => {
  const groups = groupOlympusAgents([workspaceEvent()]);
  assert.equal(groups.length, 1);
  assert.deepEqual(groups[0].agents, []);
  const workspace = parseOlympusWorkspace(workspaceEvent());
  assert.deepEqual(
    workspace.providers.map((provider) => provider.name),
    ["anthropic", "local"],
  );
});

test("ignores a workspace with the wrong version", () => {
  const event = workspaceEvent({
    content: { v: 2, name: "dev" },
  });
  assert.equal(parseOlympusWorkspace(event), null);
});

test("lists models of the pool and addable MCP servers", () => {
  const workspace = parseOlympusWorkspace(workspaceEvent());
  const agent = parseOlympusAgent(stateEvent({ id: "e1" }));
  assert.deepEqual(olympusModelOptions(workspace, "anthropic"), [
    "claude-haiku-5-5",
  ]);
  assert.deepEqual(olympusModelOptions(workspace, "local"), []);
  assert.deepEqual(olympusModelOptions(null, "anthropic"), []);
  assert.deepEqual(olympusAddableMcpServers(workspace, agent), ["search"]);
});
