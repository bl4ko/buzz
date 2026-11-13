import assert from "node:assert/strict";
import test from "node:test";

import {
  countOlympusProposals,
  countPendingOlympusProposals,
  decodeOlympusDiffValue,
  filterOlympusProposals,
  isOlympusLongDiff,
  isOlympusProposalOpen,
  listOlympusProposals,
  nextOlympusProposalExpiry,
  olympusLineDiff,
  olympusProposalStatus,
  parseOlympusProposal,
} from "./olympusProposals.ts";

const OPERATOR = "b".repeat(64);
const STRANGER = "c".repeat(64);
const OWNER = "a".repeat(64);
const ZEUS = "b921c593769ebf9081ea70bec5bf8f95fb821ee0e1bfdf1df72c0acedafa1bae";
const DIGEST = "e".repeat(64);
const TRUSTED = new Set([OPERATOR]);

function content(overrides = {}) {
  return {
    v: 1,
    name: "p-aada7279a890",
    requester: "zeus/zeus",
    requesterKey: null,
    target: {
      kind: "Agent",
      namespace: "olympus-dev",
      name: "proof",
      workspace: "dev",
    },
    operation: "patch",
    patch: { spec: { suspend: true } },
    reason: "Live proof of the <b>flow</b>\n**not markdown**",
    diff: [{ path: "spec.suspend", from: "false", to: "true" }],
    highRisk: [],
    createdAt: 1_000,
    expiresAt: 1_000 + 86_400,
    digest: DIGEST,
    phase: "pending",
    result: null,
    ...overrides,
  };
}

function proposalEvent({
  body = content(),
  pubkey = OPERATOR,
  d = "p-aada7279a890",
  status = "active",
  createdAt = 1_000,
  id = "1".repeat(64),
  requester = ZEUS,
} = {}) {
  return {
    id,
    pubkey,
    kind: 30192,
    created_at: createdAt,
    content: typeof body === "string" ? body : JSON.stringify(body),
    tags: [
      ["d", d],
      ["p", OWNER],
      ["p", OPERATOR],
      ["workspace", "dev"],
      ...(requester ? [["requester", requester]] : []),
      ["status", status],
    ],
    sig: "",
  };
}

test("parses a pending proposal with the requester key from the tag", () => {
  const proposal = parseOlympusProposal(proposalEvent(), TRUSTED);
  assert.deepEqual(proposal, {
    author: OPERATOR,
    eventId: "1".repeat(64),
    name: "p-aada7279a890",
    workspace: "dev",
    requester: "zeus/zeus",
    requesterKey: ZEUS,
    target: { kind: "Agent", namespace: "olympus-dev", name: "proof" },
    operation: "patch",
    reason: "Live proof of the <b>flow</b>\n**not markdown**",
    diff: [{ path: "spec.suspend", from: "false", to: "true" }],
    diffTruncated: false,
    highRisk: [],
    createdAt: 1_000,
    expiresAt: 87_400,
    digest: DIGEST,
    phase: "pending",
    result: null,
  });
  assert.equal(isOlympusProposalOpen(proposal, 2_000), true);
  assert.equal(isOlympusProposalOpen(proposal, 87_400), false);
});

test("keeps high-risk marks, null diff values, a truncated diff, and the result", () => {
  const proposal = parseOlympusProposal(
    proposalEvent({
      requester: null,
      body: content({
        requesterKey: ZEUS.toUpperCase(),
        target: {
          kind: "Workspace",
          namespace: null,
          name: "dev",
          workspace: "dev",
        },
        diff: [{ path: "spec.quota", from: null, to: '{"cpu":…' }],
        highRisk: ["secrets", "master agent", 7],
        phase: "applied",
        result: { reason: "applied", request: "f".repeat(64), at: 2_000 },
      }),
    }),
    TRUSTED,
  );
  assert.equal(proposal?.requesterKey, ZEUS);
  assert.deepEqual(proposal?.target, {
    kind: "Workspace",
    namespace: null,
    name: "dev",
  });
  assert.deepEqual(proposal?.diff, [
    { path: "spec.quota", from: null, to: '{"cpu":…' },
  ]);
  assert.deepEqual(proposal?.highRisk, ["secrets", "master agent"]);
  assert.deepEqual(proposal?.result, {
    reason: "applied",
    request: "f".repeat(64),
    at: 2_000,
  });
  assert.equal(isOlympusProposalOpen(proposal, 2_000), false);

  const truncated = parseOlympusProposal(
    proposalEvent({ body: content({ diff: [], diffTruncated: true }) }),
    TRUSTED,
  );
  assert.equal(truncated?.diffTruncated, true);
  assert.deepEqual(truncated?.diff, []);
});

test("ignores other authors, tombstones, and malformed content", () => {
  assert.equal(
    parseOlympusProposal(proposalEvent({ pubkey: STRANGER }), TRUSTED),
    null,
  );
  assert.equal(
    parseOlympusProposal(
      proposalEvent({ status: "deleted", body: "" }),
      TRUSTED,
    ),
    null,
  );
  const bad = [
    "not json",
    content({ v: 2 }),
    content({ name: "p-other" }),
    content({ target: { kind: "Pod", name: "proof", workspace: "dev" } }),
    content({ target: { kind: "Agent", name: "proof", workspace: "prod" } }),
    content({ operation: "replace" }),
    content({ phase: "done" }),
    content({ digest: "abc" }),
    content({ diff: [{ path: "spec.suspend", from: 1, to: "true" }] }),
    content({ diff: null }),
    content({ reason: null }),
    content({ expiresAt: "soon" }),
  ];
  for (const body of bad) {
    assert.equal(parseOlympusProposal(proposalEvent({ body }), TRUSTED), null);
  }
  assert.equal(
    parseOlympusProposal({ ...proposalEvent(), kind: 30190 }, TRUSTED),
    null,
  );
});

test("lists the newest state of each proposal, newest first", () => {
  const older = proposalEvent({
    body: content({ name: "p-old", createdAt: 500 }),
    d: "p-old",
    id: "2".repeat(64),
  });
  const pending = proposalEvent({ id: "3".repeat(64), createdAt: 1_000 });
  const applied = proposalEvent({
    id: "4".repeat(64),
    createdAt: 1_100,
    body: content({ phase: "applied" }),
  });
  const forged = proposalEvent({
    pubkey: STRANGER,
    d: "p-forged",
    body: content({ name: "p-forged", createdAt: 9_000 }),
  });
  const list = listOlympusProposals([older, pending, applied, forged], TRUSTED);
  assert.deepEqual(
    list.map((proposal) => [proposal.name, proposal.phase]),
    [
      ["p-aada7279a890", "applied"],
      ["p-old", "pending"],
    ],
  );
  const tombstone = proposalEvent({
    id: "5".repeat(64),
    createdAt: 1_200,
    status: "deleted",
    body: "",
  });
  assert.deepEqual(
    listOlympusProposals([pending, tombstone], TRUSTED).map((p) => p.name),
    [],
  );
});

function proposalAt(name, overrides = {}) {
  return parseOlympusProposal(
    proposalEvent({ d: name, body: content({ name, ...overrides }) }),
    TRUSTED,
  );
}

test("status, filters, and counts treat a pending proposal past expiresAt as expired", () => {
  const now = 100_000;
  const proposals = [
    proposalAt("p-open", { createdAt: now - 60, expiresAt: now + 60 }),
    proposalAt("p-late", { createdAt: now - 90_000, expiresAt: now - 1 }),
    proposalAt("p-edge", { createdAt: now - 86_400, expiresAt: now }),
    proposalAt("p-applied", { createdAt: now - 30, phase: "applied" }),
    proposalAt("p-rejected", { createdAt: now - 20, phase: "rejected" }),
    proposalAt("p-refused", { createdAt: now - 10, phase: "refused" }),
    proposalAt("p-failed", { createdAt: now - 5, phase: "failed" }),
    proposalAt("p-expired", { createdAt: now - 100, phase: "expired" }),
  ];
  const table = [
    ["p-open", "pending"],
    ["p-late", "expired"],
    ["p-edge", "expired"],
    ["p-applied", "applied"],
    ["p-expired", "expired"],
  ];
  for (const [name, expected] of table) {
    const proposal = proposals.find((item) => item.name === name);
    assert.equal(olympusProposalStatus(proposal, now), expected, name);
  }
  assert.deepEqual(countOlympusProposals(proposals, now), {
    pending: 1,
    applied: 1,
    rejected: 1,
    refused: 1,
    failed: 1,
    expired: 3,
    all: 8,
  });
  assert.deepEqual(
    filterOlympusProposals(proposals, "expired", now).map((p) => p.name),
    ["p-expired", "p-edge", "p-late"],
  );
  assert.deepEqual(
    filterOlympusProposals(proposals, "all", now).map((p) => p.name),
    [
      "p-failed",
      "p-refused",
      "p-rejected",
      "p-applied",
      "p-open",
      "p-expired",
      "p-edge",
      "p-late",
    ],
  );
});

test("counts open proposals for one requester and finds the next expiry", () => {
  const now = 100_000;
  const proposals = [
    proposalAt("p-a", { requesterKey: ZEUS, expiresAt: now + 500 }),
    proposalAt("p-b", { requesterKey: STRANGER, expiresAt: now + 100 }),
    proposalAt("p-c", { requesterKey: ZEUS, expiresAt: now - 1 }),
    proposalAt("p-d", {
      requesterKey: ZEUS,
      phase: "applied",
      expiresAt: now + 9,
    }),
  ];
  assert.equal(countPendingOlympusProposals(proposals, now), 2);
  assert.equal(countPendingOlympusProposals(proposals, now, ZEUS), 1);
  assert.equal(countPendingOlympusProposals(proposals, now, OWNER), 0);
  assert.equal(nextOlympusProposalExpiry(proposals, now), now + 100);
  assert.equal(nextOlympusProposalExpiry([], now), null);
});

test("decodes JSON diff values, also when the operator cut them", () => {
  assert.deepEqual(decodeOlympusDiffValue("true"), {
    text: "true",
    truncated: false,
  });
  assert.deepEqual(decodeOlympusDiffValue('"a\\nb"'), {
    text: "a\nb",
    truncated: false,
  });
  assert.deepEqual(decodeOlympusDiffValue('"line 1\\nline 2'), {
    text: "line 1\nline 2",
    truncated: true,
  });
  assert.deepEqual(decodeOlympusDiffValue('"cut at an escape\\'), {
    text: "cut at an escape",
    truncated: true,
  });
  assert.deepEqual(decodeOlympusDiffValue('{"cpu":…'), {
    text: '{"cpu":…',
    truncated: false,
  });
  const object = decodeOlympusDiffValue(
    JSON.stringify({
      name: "share",
      tools: [
        "upload_file",
        "list_files",
        "read_file",
        "delete_file",
        "move_file",
      ],
    }),
  );
  assert.ok(object.text.includes('\n  "tools": ['));
  assert.equal(decodeOlympusDiffValue(null), null);
});

test("long diff: a newline or more than 80 characters on either side", () => {
  const short = { text: "x".repeat(80), truncated: false };
  const long = { text: "x".repeat(81), truncated: false };
  const multi = { text: "a\nb", truncated: false };
  assert.equal(isOlympusLongDiff(short, short), false);
  assert.equal(isOlympusLongDiff(short, null), false);
  assert.equal(isOlympusLongDiff(null, long), true);
  assert.equal(isOlympusLongDiff(multi, short), true);
});

test("line diff keeps unchanged lines and marks removed and added ones", () => {
  assert.deepEqual(olympusLineDiff("a\nb\nc\nd", "a\nB\nc\nd\ne"), [
    { type: "same", text: "a" },
    { type: "del", text: "b" },
    { type: "add", text: "B" },
    { type: "same", text: "c" },
    { type: "same", text: "d" },
    { type: "add", text: "e" },
  ]);
  assert.deepEqual(olympusLineDiff(null, "x\ny"), [
    { type: "add", text: "x" },
    { type: "add", text: "y" },
  ]);
  assert.deepEqual(olympusLineDiff("x", null), [{ type: "del", text: "x" }]);
  assert.deepEqual(olympusLineDiff("same", "same"), [
    { type: "same", text: "same" },
  ]);
  const big = Array.from({ length: 600 }, (_, index) => `l${index}`);
  const changed = olympusLineDiff(
    big.join("\n"),
    [...big].reverse().join("\n"),
  );
  assert.equal(changed.filter((line) => line.type === "del").length, 600);
  assert.equal(changed.filter((line) => line.type === "add").length, 600);
});
