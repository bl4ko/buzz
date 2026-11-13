import assert from "node:assert/strict";
import test from "node:test";

import {
  isBotProfile,
  latestRosters,
  notificationAgentKeys,
  resolveChannelNotificationLevel,
  shouldAlertForChannelMessage,
} from "./channelLevels.ts";

const ME = "a".repeat(64);
const BOT = "b".repeat(64);
const HUMAN = "c".repeat(64);
const CHANNEL = { id: "chan", channelType: "stream" };
const DM = { id: "dm", channelType: "dm" };

function message(pubkey, tags = []) {
  return {
    id: "e".repeat(64),
    pubkey,
    created_at: 1,
    kind: 9,
    tags: [["h", "chan"], ...tags],
    content: "hi",
    sig: "s".repeat(128),
  };
}

function alert(event, { level, explicit = false, isDm = false } = {}) {
  const explicitLevels = new Map(explicit ? [[CHANNEL.id, level]] : []);
  const agentChannels = new Set(
    level === "mentions" && !explicit ? [CHANNEL.id] : [],
  );
  const resolution = resolveChannelNotificationLevel(
    isDm ? DM : CHANNEL,
    explicitLevels,
    agentChannels,
  );
  return shouldAlertForChannelMessage(event, ME, {
    resolution,
    isDm,
    botPubkeys: new Set([BOT]),
  });
}

test("defaults: agent channels are mentions, others all, DMs all", () => {
  const agentChannels = new Set(["chan", "dm"]);
  assert.deepEqual(
    resolveChannelNotificationLevel(CHANNEL, new Map(), agentChannels),
    { level: "mentions", isExplicit: false, defaultLevel: "mentions" },
  );
  assert.equal(
    resolveChannelNotificationLevel(DM, new Map(), agentChannels).level,
    "all",
  );
  assert.deepEqual(
    resolveChannelNotificationLevel(
      CHANNEL,
      new Map([["chan", "all"]]),
      agentChannels,
    ),
    { level: "all", isExplicit: true, defaultLevel: "mentions" },
  );
});

test("default all: human posts alert, bot posts stay quiet", () => {
  assert.equal(alert(message(HUMAN), { level: "all" }), true);
  assert.equal(alert(message(BOT), { level: "all" }), false);
});

test("explicit all: bot posts alert too", () => {
  assert.equal(alert(message(BOT), { level: "all", explicit: true }), true);
});

test("mentions: top-level posts are quiet; mentions, approvals, replies, DMs alert", () => {
  assert.equal(alert(message(HUMAN), { level: "mentions" }), false);
  assert.equal(alert(message(BOT, [["p", ME]]), { level: "mentions" }), true);
  assert.equal(
    alert(message(BOT, [["notification", "approval"]]), { level: "mentions" }),
    true,
  );
  assert.equal(
    alert(
      message(HUMAN, [
        ["e", "f".repeat(64), "", "root"],
        ["e", "d".repeat(64), "", "reply"],
      ]),
      {
        level: "mentions",
      },
    ),
    true,
  );
  assert.equal(alert(message(BOT), { level: "all", isDm: true }), true);
});

test("nothing: no alert, also not for mentions or DMs", () => {
  assert.equal(
    alert(message(HUMAN, [["p", ME]]), { level: "nothing", explicit: true }),
    false,
  );
  const resolution = resolveChannelNotificationLevel(
    DM,
    new Map([["dm", "nothing"]]),
    new Set(),
  );
  assert.equal(
    shouldAlertForChannelMessage(message(BOT), ME, {
      resolution,
      isDm: true,
      botPubkeys: new Set(),
    }),
    false,
  );
});

test("agent keys: NIP-24 bot profiles mark their channels", () => {
  const roster = (d, members, createdAt) => ({
    id: d,
    pubkey: "r".repeat(64),
    created_at: createdAt,
    kind: 39002,
    tags: [["d", d], ...members.map((pubkey) => ["p", pubkey])],
    content: "",
    sig: "",
  });
  const profile = (pubkey, content) => ({
    id: pubkey,
    pubkey,
    created_at: 1,
    kind: 0,
    tags: [],
    content,
    sig: "",
  });
  const rosters = latestRosters([
    roster("agents", [ME, BOT], 2),
    roster("humans", [ME, HUMAN], 2),
    roster("humans", [ME, BOT], 1),
  ]);
  const keys = notificationAgentKeys(rosters, [
    profile(BOT, JSON.stringify({ name: "zeus", bot: true })),
    profile(HUMAN, JSON.stringify({ name: "ann", bot: "true" })),
  ]);
  assert.deepEqual([...keys.botPubkeys], [BOT]);
  assert.deepEqual([...keys.agentChannelIds], ["agents"]);
  assert.equal(isBotProfile({ content: "not json" }), false);
});
