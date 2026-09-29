import assert from "node:assert/strict";
import test from "node:test";

import {
  isHuddleBackingChannel,
  shouldShowSidebarChannel,
} from "./huddleChannelVisibility.ts";

function channel(overrides = {}) {
  return {
    id: "channel-id",
    name: "general",
    ttlSeconds: null,
    ...overrides,
  };
}

test("ordinary channels stay visible", () => {
  assert.equal(shouldShowSidebarChannel(channel(), new Set()), true);
});

test("tracked huddle backing channels stay hidden by default", () => {
  const huddle = channel({
    id: "stale-huddle",
    name: "general huddle",
    ttlSeconds: 3_600,
  });
  const huddleBackingChannelIds = new Set([huddle.id]);

  assert.equal(isHuddleBackingChannel(huddle, huddleBackingChannelIds), true);
  assert.equal(
    shouldShowSidebarChannel(huddle, huddleBackingChannelIds),
    false,
  );
});

test("an active huddle backing channel stays out of the sidebar", () => {
  const huddle = channel({
    id: "active-huddle",
    name: "huddle",
    ttlSeconds: 3_600,
  });

  assert.equal(shouldShowSidebarChannel(huddle, new Set([huddle.id])), false);
});

test("one-hour channels with huddle-shaped names remain ordinary", () => {
  const ordinaryChannel = channel({
    name: "design huddle",
    ttlSeconds: 3_600,
  });

  assert.equal(isHuddleBackingChannel(ordinaryChannel, new Set()), false);
  assert.equal(shouldShowSidebarChannel(ordinaryChannel, new Set()), true);
});

test("mobile huddle channels stay out of the desktop sidebar", () => {
  const huddle = channel({
    name: "huddle-cb879efb",
    channelType: "stream",
    visibility: "private",
    ttlSeconds: 3_600,
  });
  assert.equal(shouldShowSidebarChannel(huddle, new Set()), false);
});
