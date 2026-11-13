import assert from "node:assert/strict";
import test from "node:test";

import {
  buildAskDraft,
  findMasterAgent,
  findMasterDm,
  masterAgentLabel,
  masterAgentPicture,
  mergeAskDraft,
  quoteMarkdown,
} from "./masterAgent.ts";

const ME = "a".repeat(64);
const MASTER = "d".repeat(64);
const OTHER = "e".repeat(64);

function agent(overrides = {}) {
  return {
    name: "zeus",
    workspace: "zeus",
    role: "master",
    publicKey: MASTER,
    phase: "Online",
    spec: { profile: { displayName: "Zeus", picture: "https://x/z.png" } },
    ...overrides,
  };
}

function groups(...agents) {
  return [{ key: "k", name: "ws", author: "b", workspace: null, agents }];
}

test("finds the agent with the master role", () => {
  const master = agent();
  assert.equal(
    findMasterAgent(groups(agent({ role: null, name: "argus" }), master)),
    master,
  );
});

test("no master role, or no enrolled key, means no master", () => {
  assert.equal(findMasterAgent(groups(agent({ role: null }))), null);
  assert.equal(findMasterAgent(groups(agent({ publicKey: null }))), null);
  assert.equal(findMasterAgent([]), null);
});

test("prefers a running master over a suspended one, then by name", () => {
  const suspended = agent({ name: "a", workspace: "a", phase: "Suspended" });
  const running = agent({ name: "z", workspace: "z" });
  assert.equal(findMasterAgent(groups(suspended, running)), running);
  const first = agent({ name: "alpha" });
  assert.equal(findMasterAgent(groups(agent({ name: "beta" }), first)), first);
});

test("label comes from the profile, never a fixed name", () => {
  const record = agent({ name: "boss", spec: { profile: null } });
  assert.equal(masterAgentLabel(record, { displayName: "Odin" }), "Odin");
  assert.equal(masterAgentLabel(record, { displayName: " ", name: "o" }), "o");
  assert.equal(masterAgentLabel(record, undefined), "boss");
  assert.equal(masterAgentLabel(agent(), undefined), "Zeus");
});

test("picture comes from the kind 0 profile, else the agent spec", () => {
  assert.equal(
    masterAgentPicture(agent(), { avatarUrl: "https://y" }),
    "https://y",
  );
  assert.equal(masterAgentPicture(agent(), null), "https://x/z.png");
  assert.equal(
    masterAgentPicture(agent({ spec: { profile: null } }), null),
    null,
  );
});

test("finds the one-to-one DM with the master", () => {
  const dm = {
    id: "dm",
    channelType: "dm",
    participantPubkeys: [ME, MASTER.toUpperCase()],
  };
  const group = {
    id: "group",
    channelType: "dm",
    participantPubkeys: [ME, MASTER, OTHER],
  };
  const stream = {
    id: "s",
    channelType: "stream",
    participantPubkeys: [ME, MASTER],
  };
  assert.equal(findMasterDm([stream, group, dm], ME, MASTER), dm);
  assert.equal(findMasterDm([stream, group], ME, MASTER), null);
});

test("quotes every line and keeps paragraph breaks", () => {
  assert.equal(quoteMarkdown("a\r\n\r\nb  \n"), "> a\n>\n> b");
  assert.ok(quoteMarkdown("x".repeat(9_000)).endsWith("…"));
});

test("draft has the quote, then the link with room to type", () => {
  assert.equal(
    buildAskDraft({ quote: "why?", link: "buzz://message?channel=c&id=i" }),
    "> why?\n\nbuzz://message?channel=c&id=i ",
  );
  assert.equal(buildAskDraft({ quote: "  " }), "");
  assert.equal(buildAskDraft({}), "");
});

test("a new ask is added to an existing draft once", () => {
  assert.equal(mergeAskDraft(undefined, "> a"), "> a");
  assert.equal(mergeAskDraft("hello  ", "> a"), "hello\n\n> a");
  assert.equal(mergeAskDraft("hello\n\n> a", "> a"), "hello\n\n> a");
});
