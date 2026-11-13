import assert from "node:assert/strict";
import test from "node:test";

import {
  olympusOwnedAgents,
  olympusOwnedAgentsKey,
} from "./olympusOwnedAgents.ts";

const ME = "a".repeat(64);
const OTHER = "c".repeat(64);
const ZEUS = "9".repeat(64);
const ARGUS = "1".repeat(64);

function agent(name, overrides = {}) {
  return {
    name,
    owner: ME,
    publicKey: null,
    phase: "Online",
    spec: { profile: null },
    ...overrides,
  };
}

const groups = [
  {
    agents: [
      agent("zeus", {
        publicKey: ZEUS,
        spec: { profile: { displayName: " Zeus ", picture: null } },
      }),
      agent("argus", { publicKey: ARGUS, phase: "Suspended" }),
      agent("pending"),
      agent("foreign", { publicKey: "2".repeat(64), owner: OTHER }),
      agent("ownerless", { publicKey: "3".repeat(64), owner: null }),
    ],
  },
  { agents: [agent("zeus-copy", { publicKey: ZEUS })] },
];

test("keeps only enrolled agents that the viewer owns", () => {
  assert.deepEqual(olympusOwnedAgents(groups, ME.toUpperCase()), [
    { pubkey: ARGUS, name: "argus", status: "stopped" },
    { pubkey: ZEUS, name: "Zeus", status: "deployed" },
  ]);
  assert.deepEqual(
    olympusOwnedAgents(groups, OTHER).map((a) => a.name),
    ["foreign"],
  );
  assert.deepEqual(olympusOwnedAgents(groups, ""), []);
  assert.deepEqual(olympusOwnedAgents(groups, undefined), []);
});

test("the key changes with the key set, the status, and the name", () => {
  const base = olympusOwnedAgents(groups, ME);
  assert.equal(olympusOwnedAgentsKey(base), olympusOwnedAgentsKey([...base]));
  assert.notEqual(
    olympusOwnedAgentsKey(base),
    olympusOwnedAgentsKey([{ ...base[0], status: "deployed" }, base[1]]),
  );
});

test("the kind 0 display name wins over the spec name", () => {
  const named = olympusOwnedAgents(groups, ME, {
    [ZEUS]: { displayName: "Zeus Prime", name: "zeus" },
    [ARGUS]: { displayName: null, name: "Argus" },
  });
  assert.deepEqual(
    named.map((agent) => agent.name),
    ["Argus", "Zeus Prime"],
  );
});
