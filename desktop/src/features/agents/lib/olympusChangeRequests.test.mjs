import assert from "node:assert/strict";
import test from "node:test";

import {
  buildOlympusChangeRequest,
  getOlympusRequestState,
  parseOlympusChangeResult,
  resetOlympusChangeRequests,
  submitOlympusChange,
} from "./olympusChangeRequests.ts";

const OPERATOR = "b".repeat(64);
const ME = "a".repeat(64);
const AGENT = { operator: OPERATOR, workspace: "dev", agent: "proof" };
const WORKSPACE = { operator: OPERATOR, workspace: "dev", agent: null };

function build(target, change) {
  const template = buildOlympusChangeRequest(target, change);
  return { ...template, content: JSON.parse(template.content) };
}

test("builds agent suspend, resume, and delete requests", () => {
  for (const action of ["suspend", "resume", "delete"]) {
    assert.deepEqual(build(AGENT, { action }), {
      kind: 44310,
      tags: [
        ["p", OPERATOR],
        ["workspace", "dev"],
        ["agent", "proof"],
        ["action", action],
      ],
      content: { v: 1, action, workspace: "dev", agent: "proof" },
    });
  }
});

test("builds workspace suspend and resume without an agent tag", () => {
  for (const action of ["suspend", "resume"]) {
    assert.deepEqual(build(WORKSPACE, { action }), {
      kind: 44310,
      tags: [
        ["p", OPERATOR],
        ["workspace", "dev"],
        ["action", action],
      ],
      content: { v: 1, action, workspace: "dev" },
    });
  }
});

test("builds update with only the changed fields and null clears", () => {
  assert.deepEqual(
    build(AGENT, { action: "update", model: "claude-opus-5-5" }).content,
    {
      v: 1,
      action: "update",
      workspace: "dev",
      agent: "proof",
      model: "claude-opus-5-5",
    },
  );
  assert.deepEqual(
    build(AGENT, { action: "update", effort: null, instructions: null })
      .content,
    {
      v: 1,
      action: "update",
      workspace: "dev",
      agent: "proof",
      effort: null,
      instructions: null,
    },
  );
});

test("builds MCP, memory, and create requests", () => {
  assert.deepEqual(
    build(AGENT, { action: "add-mcp", server: { name: "search" } }).content
      .server,
    { name: "search" },
  );
  assert.equal(
    build(AGENT, { action: "remove-mcp", server: "share" }).content.server,
    "share",
  );
  assert.deepEqual(
    build(AGENT, { action: "set-memory", memory: { bank: "workspace" } })
      .content.memory,
    { bank: "workspace" },
  );
  assert.equal(
    build(AGENT, { action: "set-memory", memory: null }).content.memory,
    null,
  );
  const create = build(
    { ...WORKSPACE, agent: "new-one" },
    {
      action: "create",
      harness: "codex",
      pool: "openai",
      model: "gpt-5",
      effort: "low",
    },
  );
  assert.deepEqual(create.tags, [
    ["p", OPERATOR],
    ["workspace", "dev"],
    ["agent", "new-one"],
    ["action", "create"],
  ]);
  assert.deepEqual(create.content, {
    v: 1,
    action: "create",
    workspace: "dev",
    agent: "new-one",
    harness: "codex",
    pool: "openai",
    model: "gpt-5",
    effort: "low",
  });
});

test("refuses to build requests without a valid target", () => {
  assert.throws(() =>
    buildOlympusChangeRequest(
      { ...AGENT, operator: "xyz" },
      { action: "suspend" },
    ),
  );
  assert.throws(() =>
    buildOlympusChangeRequest(WORKSPACE, { action: "delete" }),
  );
  assert.throws(() =>
    buildOlympusChangeRequest(
      { ...AGENT, workspace: "" },
      { action: "resume" },
    ),
  );
});

const DIGEST = "e".repeat(64);

test("builds proposal approve and reject requests without an agent tag", () => {
  for (const action of ["approve", "reject"]) {
    assert.deepEqual(
      build(WORKSPACE, { action, proposal: "p-aada7279a890", digest: DIGEST }),
      {
        kind: 44310,
        tags: [
          ["p", OPERATOR],
          ["workspace", "dev"],
          ["action", action],
          ["proposal", "p-aada7279a890"],
        ],
        content: {
          v: 1,
          action,
          workspace: "dev",
          proposal: "p-aada7279a890",
          digest: DIGEST,
        },
      },
    );
  }
  const template = buildOlympusChangeRequest(WORKSPACE, {
    action: "approve",
    proposal: "p-1",
    digest: DIGEST,
    highRisk: true,
  });
  assert.equal(
    template.content,
    `{"v":1,"action":"approve","workspace":"dev","proposal":"p-1","digest":"${DIGEST}","highRisk":true}`,
  );
});

test("refuses a proposal request with an agent or a bad digest", () => {
  const change = { action: "approve", proposal: "p-1", digest: DIGEST };
  assert.throws(() => buildOlympusChangeRequest(AGENT, change));
  assert.throws(() =>
    buildOlympusChangeRequest(WORKSPACE, { ...change, digest: "abc" }),
  );
  assert.throws(() =>
    buildOlympusChangeRequest(WORKSPACE, { ...change, proposal: "" }),
  );
});

function resultEvent({ requestId, status, reason, eTags }) {
  return {
    id: "r".repeat(64),
    pubkey: OPERATOR,
    kind: 44311,
    created_at: 1,
    tags: [
      ...(eTags ?? [["e", requestId]]),
      ["p", ME],
      ["p", OPERATOR],
      ["status", status],
    ],
    content: JSON.stringify({ v: 1, status, reason, request: requestId }),
    sig: "",
  };
}

test("ignores a result from another author", () => {
  const id = "1".repeat(64);
  const forged = {
    ...resultEvent({ requestId: id, status: "accepted" }),
    pubkey: ME,
  };
  assert.equal(parseOlympusChangeResult(forged, id, OPERATOR), null);
});

test("parses results only for the matching request", () => {
  const id = "1".repeat(64);
  assert.deepEqual(
    parseOlympusChangeResult(
      resultEvent({
        requestId: id,
        status: "refused",
        reason: "not the owner",
      }),
      id,
      OPERATOR,
    ),
    { status: "refused", reason: "not the owner" },
  );
  assert.equal(
    parseOlympusChangeResult(
      resultEvent({ requestId: "2".repeat(64), status: "accepted" }),
      id,
      OPERATOR,
    ),
    null,
  );
  assert.equal(
    parseOlympusChangeResult(
      resultEvent({
        requestId: id,
        status: "accepted",
        eTags: [
          ["e", id],
          ["e", id],
        ],
      }),
      id,
      OPERATOR,
    ),
    null,
  );
});

function fakeTransport({ answer, publishError } = {}) {
  const calls = [];
  let listener = null;
  return {
    calls,
    deliver(event) {
      listener?.(event);
    },
    transport: {
      async sign(template) {
        calls.push(["sign", template]);
        return {
          ...template,
          id: "9".repeat(64),
          pubkey: ME,
          created_at: 1,
          sig: "",
        };
      },
      async subscribe(filter, onEvent) {
        calls.push(["subscribe", filter]);
        listener = onEvent;
        return async () => {
          calls.push(["dispose"]);
          listener = null;
        };
      },
      async publish(event) {
        calls.push(["publish", event.id]);
        if (publishError) throw new Error(publishError);
        if (answer) queueMicrotask(() => listener?.(answer(event.id)));
      },
    },
  };
}

test("subscribes before publishing and records the accepted result", async () => {
  resetOlympusChangeRequests();
  const fake = fakeTransport({
    answer: (id) =>
      resultEvent({ requestId: id, status: "accepted", reason: "applied" }),
  });
  const state = await submitOlympusChange(
    { key: "dev/proof", me: ME, target: AGENT, change: { action: "suspend" } },
    fake.transport,
  );
  assert.deepEqual(state, {
    phase: "accepted",
    action: "suspend",
    reason: "applied",
  });
  assert.deepEqual(
    fake.calls.map((call) => call[0]),
    ["sign", "subscribe", "publish", "dispose"],
  );
  assert.deepEqual(fake.calls[1][1], {
    kinds: [44311],
    "#e": ["9".repeat(64)],
    "#p": [ME],
    limit: 1,
  });
  assert.deepEqual(getOlympusRequestState("dev/proof"), state);
});

test("allows one pending request per key", async () => {
  resetOlympusChangeRequests();
  const fake = fakeTransport();
  const first = submitOlympusChange(
    {
      key: "dev/proof",
      me: ME,
      target: AGENT,
      change: { action: "suspend" },
      timeoutMs: 20,
    },
    fake.transport,
  );
  assert.equal(getOlympusRequestState("dev/proof").phase, "pending");
  const second = await submitOlympusChange(
    { key: "dev/proof", me: ME, target: AGENT, change: { action: "resume" } },
    fake.transport,
  );
  assert.equal(second, null);
  const state = await first;
  assert.equal(state.phase, "failed");
  assert.match(state.reason, /30 seconds/);
});

test("reports a refused publish", async () => {
  resetOlympusChangeRequests();
  const fake = fakeTransport({ publishError: "restricted: not allowed" });
  const state = await submitOlympusChange(
    { key: "dev/proof", me: ME, target: AGENT, change: { action: "delete" } },
    fake.transport,
  );
  assert.deepEqual(state, {
    phase: "failed",
    action: "delete",
    reason: "restricted: not allowed",
  });
  assert.equal(fake.calls.at(-1)[0], "dispose");
});

test("a reset drops a pending request and its late result", async () => {
  resetOlympusChangeRequests();
  const fake = fakeTransport();
  const pending = submitOlympusChange(
    { key: "dev/proof", me: ME, target: AGENT, change: { action: "suspend" } },
    fake.transport,
  );
  await new Promise((resolve) => setTimeout(resolve, 0));
  resetOlympusChangeRequests();
  assert.equal(getOlympusRequestState("dev/proof"), null);
  assert.ok(fake.calls.some((call) => call[0] === "dispose"));
  fake.deliver(resultEvent({ requestId: "9".repeat(64), status: "accepted" }));
  assert.equal(await pending, null);
  assert.equal(getOlympusRequestState("dev/proof"), null);
});

test("schedule actions carry a schedule tag and no agent", () => {
  const target = {
    operator: OPERATOR,
    workspace: "ops",
    agent: null,
    schedule: "daily-os-updates",
  };
  for (const action of ["suspend-schedule", "resume-schedule", "run-now"]) {
    const template = buildOlympusChangeRequest(target, { action });
    assert.deepEqual(template.tags, [
      ["p", OPERATOR],
      ["workspace", "ops"],
      ["schedule", "daily-os-updates"],
      ["action", action],
    ]);
    assert.deepEqual(JSON.parse(template.content), {
      v: 1,
      action,
      workspace: "ops",
      schedule: "daily-os-updates",
    });
  }
  assert.throws(() =>
    buildOlympusChangeRequest(
      { ...target, schedule: null },
      { action: "run-now" },
    ),
  );
  assert.throws(() =>
    buildOlympusChangeRequest(
      { ...target, agent: "argus" },
      { action: "run-now" },
    ),
  );
  assert.throws(() => buildOlympusChangeRequest(target, { action: "delete" }));
});

test("patch and create with a spec carry the spec and the high-risk flag", () => {
  const agent = { operator: OPERATOR, workspace: "ops", agent: "argus" };
  const patch = buildOlympusChangeRequest(agent, {
    action: "patch",
    patch: { egress: [{ preset: "internet" }] },
    highRisk: true,
  });
  assert.deepEqual(JSON.parse(patch.content), {
    v: 1,
    action: "patch",
    workspace: "ops",
    agent: "argus",
    patch: { egress: [{ preset: "internet" }] },
    highRisk: true,
  });
  const workspacePatch = buildOlympusChangeRequest(
    { operator: OPERATOR, workspace: "ops", agent: null },
    { action: "patch", patch: { suspend: true } },
  );
  assert.deepEqual(workspacePatch.tags, [
    ["p", OPERATOR],
    ["workspace", "ops"],
    ["action", "patch"],
  ]);
  const create = buildOlympusChangeRequest(
    { operator: OPERATOR, workspace: "ops", agent: "scout" },
    { action: "create", spec: { template: "base" } },
  );
  assert.deepEqual(JSON.parse(create.content), {
    v: 1,
    action: "create",
    workspace: "ops",
    agent: "scout",
    spec: { template: "base" },
  });
});
