import { buildInboxItems } from "../../home/lib/inbox.ts";
import assert from "node:assert/strict";
import { test } from "node:test";
import { isAgentCoordination, messageAudience } from "./messageAudience.ts";
import {
  shouldNotifyForEvent,
  hasMentionForEvent,
  isHighPriorityEventForUser,
} from "../../notifications/lib/shouldNotify.ts";
import { eligibleFeedNotificationItems } from "../../notifications/lib/feed.ts";
import { buildHomeBadgeFeedItems } from "../../notifications/lib/homeBadge.ts";

const options = {
  participatedRootIds: new Set(["root"]),
  followedRootIds: new Set(["root"]),
  authoredRootIds: new Set(["root"]),
};
const event = (tags, kind = 9) => ({
  id: "a",
  kind,
  pubkey: "agent",
  created_at: 100,
  content: "hello",
  tags,
});

test("only exactly one recognized declaration opts into coordination", () => {
  assert.equal(messageAudience([["audience", "everyone"]]), "everyone");
  assert.equal(isAgentCoordination(event([["audience", "agents"]])), true);
  for (const tags of [
    [],
    [["audience"]],
    [["audience", "future"]],
    [["audience", "agents", "extra"]],
    [
      ["audience", "agents"],
      ["audience", "everyone"],
    ],
    [
      ["audience", "agents"],
      ["audience", "agents"],
    ],
  ]) {
    assert.equal(messageAudience(tags), null);
    assert.equal(isAgentCoordination(event(tags)), false);
    assert.equal(shouldNotifyForEvent(event(tags), "human", options), true);
  }
  assert.equal(isAgentCoordination(event([["audience", "agents"]], 7)), false);
});

test("coordination does not create human mentions, priority or thread alerts", () => {
  for (const extra of [
    [],
    [["p", "human"]],
    [["broadcast", "1"]],
    [["e", "root", "", "reply"]],
    [
      ["p", "human"],
      ["broadcast", "1"],
      ["e", "root", "", "reply"],
    ],
  ]) {
    const message = event([["audience", "agents"], ...extra]);
    assert.equal(shouldNotifyForEvent(message, "human", options), false);
    assert.equal(hasMentionForEvent(message, "human"), false);
    assert.equal(isHighPriorityEventForUser(message, "human"), false);
    // No mutation of routing metadata.
    assert.deepEqual(message.tags, [["audience", "agents"], ...extra]);
    assert.equal(
      shouldNotifyForEvent(
        event([["audience", "everyone"], ...extra]),
        "human",
        options,
      ),
      true,
    );
  }
});

test("coordination mentions cannot leak through home alerts or badge projection", () => {
  const makeItem = (id, audience) => ({
    ...event([
      ["audience", audience],
      ["p", "human"],
    ]),
    id,
    createdAt: 100,
    channelId: "ch",
    channelName: "test",
    channelType: "stream",
    category: "mention",
  });
  const feed = {
    feed: {
      mentions: [makeItem("coord", "agents"), makeItem("answer", "everyone")],
      needsAction: [],
      activity: [],
      agentActivity: [],
    },
  };
  assert.deepEqual(
    eligibleFeedNotificationItems(feed, {
      mentions: true,
      needsAction: true,
    }).map((item) => item.id),
    ["answer"],
  );
  assert.equal(buildInboxItems({ feed }).length, 1);
  assert.deepEqual(
    buildHomeBadgeFeedItems(feed, [], new Set()).map((item) => item.id),
    ["answer"],
  );
});
