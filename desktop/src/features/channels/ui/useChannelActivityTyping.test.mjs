import assert from "node:assert/strict";
import { beforeEach, describe, it } from "node:test";

import {
  getAgentWorkingState,
  getWorkingAgentPubkeysForChannel,
  reportChannelBotTyping,
  resetAgentWorkingSignal,
} from "../../agents/agentWorkingSignal.ts";
import { resetActiveAgentTurnsStore } from "../../agents/activeAgentTurnsStore.ts";
import {
  channelScopedBotTypingPubkeyKey,
  classifyChannelTyping,
  mergeMemberAgentFlagsIntoProfiles,
} from "./useChannelActivityTyping.ts";
import {
  buildChannelAgentSessionCandidates,
  getChannelAgentSessionAgents,
} from "./useChannelAgentSessions.ts";

const AGENT =
  "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234";
const AGENT_2 =
  "dcba4321dcba4321dcba4321dcba4321dcba4321dcba4321dcba4321dcba4321";

describe("channelScopedBotTypingPubkeyKey", () => {
  it("excludes thread-scoped typing entries", () => {
    const key = channelScopedBotTypingPubkeyKey([
      { pubkey: AGENT, threadHeadId: "thread-1" },
    ]);
    assert.equal(key, "");
  });

  it("keeps channel-scoped entries and drops thread-scoped ones", () => {
    const key = channelScopedBotTypingPubkeyKey([
      { pubkey: AGENT, threadHeadId: "thread-1" },
      { pubkey: AGENT_2, threadHeadId: null },
    ]);
    assert.equal(key, AGENT_2);
  });

  it("sorts and lowercases channel-scoped pubkeys", () => {
    const key = channelScopedBotTypingPubkeyKey([
      { pubkey: AGENT_2.toUpperCase(), threadHeadId: null },
      { pubkey: AGENT, threadHeadId: null },
    ]);
    assert.equal(key, `${AGENT},${AGENT_2}`);
  });
});

describe("thread-only bot typing regression", () => {
  beforeEach(() => {
    resetActiveAgentTurnsStore();
    resetAgentWorkingSignal();
  });

  it("does not mark channel-level working", () => {
    // The mirror effect reports only the channel-scoped key; thread-only
    // typing produces an empty key, so nothing reaches the working signal.
    const key = channelScopedBotTypingPubkeyKey([
      { pubkey: AGENT, threadHeadId: "thread-1" },
    ]);
    reportChannelBotTyping("chan-1", key ? key.split(",") : []);

    assert.deepEqual(getWorkingAgentPubkeysForChannel("chan-1"), []);
    const state = getAgentWorkingState(AGENT, "chan-1");
    assert.equal(state.working, false);
    assert.equal(state.source, "none");
  });

  it("still marks channel-level working for channel-scoped typing", () => {
    const key = channelScopedBotTypingPubkeyKey([
      { pubkey: AGENT, threadHeadId: null },
      { pubkey: AGENT_2, threadHeadId: "thread-1" },
    ]);
    reportChannelBotTyping("chan-1", key ? key.split(",") : []);

    assert.deepEqual(getWorkingAgentPubkeysForChannel("chan-1"), [AGENT]);
    const state = getAgentWorkingState(AGENT, "chan-1");
    assert.equal(state.working, true);
    assert.equal(state.source, "typing");
  });
});

describe("mergeMemberAgentFlagsIntoProfiles", () => {
  it("flags a role-only bot member (no isAgent) as an agent", () => {
    const merged = mergeMemberAgentFlagsIntoProfiles({}, [
      { pubkey: AGENT, role: "bot", isAgent: false },
    ]);

    assert.equal(merged[AGENT]?.isAgent, true);
    assert.equal(merged[AGENT]?.displayName, null);
    assert.equal(merged[AGENT]?.avatarUrl, null);
    assert.equal(merged[AGENT]?.nip05Handle, null);
    assert.equal(merged[AGENT]?.ownerPubkey, null);
  });

  it("flags an isAgent-only member (non-bot role) as an agent", () => {
    const merged = mergeMemberAgentFlagsIntoProfiles({}, [
      { pubkey: AGENT, role: "member", isAgent: true },
    ]);

    assert.equal(merged[AGENT]?.isAgent, true);
  });

  it("normalises member pubkeys so lookups by normalised key hit", () => {
    const merged = mergeMemberAgentFlagsIntoProfiles({}, [
      { pubkey: ` ${AGENT.toUpperCase()}`, role: "bot", isAgent: false },
    ]);

    assert.equal(merged[AGENT]?.isAgent, true);
  });

  it("returns the same reference when no member carries an agent flag", () => {
    const profiles = {
      [AGENT]: {
        displayName: "Human",
        avatarUrl: null,
        nip05Handle: null,
        ownerPubkey: null,
      },
    };

    assert.equal(
      mergeMemberAgentFlagsIntoProfiles(profiles, undefined),
      profiles,
    );
    assert.equal(mergeMemberAgentFlagsIntoProfiles(profiles, []), profiles);
    assert.equal(
      mergeMemberAgentFlagsIntoProfiles(profiles, [
        { pubkey: AGENT_2, role: "member", isAgent: false },
      ]),
      profiles,
    );
  });

  it("preserves existing profile fields and does not mutate the input", () => {
    const profiles = {
      [AGENT]: {
        displayName: "Deploy Bot",
        name: "deploybot",
        avatarUrl: "https://example.com/a.png",
        nip05Handle: "deploy@example.com",
        ownerPubkey: AGENT_2,
      },
    };

    const merged = mergeMemberAgentFlagsIntoProfiles(profiles, [
      { pubkey: AGENT, role: "bot", isAgent: false },
    ]);

    assert.notEqual(merged, profiles);
    assert.deepEqual(merged[AGENT], {
      displayName: "Deploy Bot",
      name: "deploybot",
      avatarUrl: "https://example.com/a.png",
      nip05Handle: "deploy@example.com",
      ownerPubkey: AGENT_2,
      isAgent: true,
    });
    assert.equal(profiles[AGENT].isAgent, undefined);
  });
});

describe("Olympus agents in channel typing", () => {
  const ME = "a".repeat(64);
  const ZEUS = "9".repeat(64);
  const HUMAN = "4".repeat(64);
  const dm = {
    id: "dm-zeus",
    name: "zeus",
    channelType: "dm",
    participantPubkeys: [ME, ZEUS],
  };
  const members = [
    { pubkey: ME, role: "owner", isAgent: false, displayName: "me" },
    { pubkey: ZEUS, role: "member", isAgent: false, displayName: "Zeus" },
    { pubkey: HUMAN, role: "member", isAgent: false, displayName: "Ana" },
  ];
  const typing = [
    { pubkey: ZEUS, threadHeadId: null },
    { pubkey: ZEUS, threadHeadId: "thread-1" },
    { pubkey: HUMAN, threadHeadId: null },
  ];

  function classify(olympusAgents) {
    const agents = getChannelAgentSessionAgents({
      activeChannel: dm,
      activeChannelId: dm.id,
      agents: buildChannelAgentSessionCandidates({
        channelMembers: members,
        managedAgents: [],
        olympusAgents,
        relayAgents: [],
      }),
      channelMembers: members,
    });
    return {
      agents,
      ...classifyChannelTyping({
        channelAgentPubkeys: new Set(agents.map((agent) => agent.pubkey)),
        openThreadHeadId: "thread-1",
        typingEntries: typing,
      }),
    };
  }

  it("treats an owned Olympus agent's typing as agent work, also in a thread", () => {
    const result = classify([
      { pubkey: ZEUS, name: "Zeus", status: "deployed" },
    ]);
    assert.deepEqual(
      result.agents.map((agent) => [agent.pubkey, agent.agentSource]),
      [[ZEUS, "relay"]],
    );
    assert.deepEqual(result.botTypingEntries, typing.slice(0, 2));
    assert.deepEqual(result.humanTypingPubkeys, [HUMAN]);
    assert.deepEqual(result.threadTypingPubkeys, []);
  });

  it("without the Olympus agent the same typing is human typing", () => {
    const result = classify([]);
    assert.deepEqual(result.agents, []);
    assert.deepEqual(result.botTypingEntries, []);
    assert.deepEqual(result.humanTypingPubkeys, [ZEUS, HUMAN]);
    assert.deepEqual(result.threadTypingPubkeys, [ZEUS]);
  });

  it("does not count an Olympus agent that is not a member of the channel", () => {
    const result = classify([
      { pubkey: "7".repeat(64), name: "Argus", status: "deployed" },
    ]);
    assert.deepEqual(result.agents, []);
  });
});
