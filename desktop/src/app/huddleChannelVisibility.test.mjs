import assert from "node:assert/strict";
import test from "node:test";

import {
  isHuddleBackingChannel,
  shouldShowSidebarChannel,
} from "./huddleChannelVisibility.ts";

const NONE = new Set();

function channel(overrides = {}) {
  return {
    id: "channel-id",
    name: "general",
    channelType: "stream",
    visibility: "open",
    ttlSeconds: null,
    archivedAt: null,
    ...overrides,
  };
}

test("ordinary channels stay visible until archived", () => {
  assert.equal(shouldShowSidebarChannel(channel(), NONE, NONE), true);
  assert.equal(
    shouldShowSidebarChannel(channel({ archivedAt: 1 }), NONE, NONE),
    false,
  );
});

test("tracked huddle backing channels stay out of the sidebar", () => {
  const huddle = channel({
    id: "desktop-huddle",
    name: "general huddle",
    visibility: "private",
    ttlSeconds: 3_600,
  });
  const tracked = new Set([huddle.id]);
  assert.equal(isHuddleBackingChannel(huddle, tracked), true);
  assert.equal(shouldShowSidebarChannel(huddle, tracked, NONE), false);
});

test("mobile huddle backing channels stay out of the sidebar", () => {
  const huddle = channel({
    name: "huddle-cb879efb",
    visibility: "private",
    ttlSeconds: 3_600,
  });
  assert.equal(shouldShowSidebarChannel(huddle, NONE, NONE), false);
});

test("an old huddle channel opened from its card is shown until archived", () => {
  const huddle = channel({
    id: "old-huddle",
    name: "huddle-cb879efb",
    visibility: "private",
    ttlSeconds: 3_600,
  });
  const revealed = new Set([huddle.id]);
  assert.equal(shouldShowSidebarChannel(huddle, NONE, revealed), true);
  assert.equal(
    shouldShowSidebarChannel({ ...huddle, archivedAt: 1 }, NONE, revealed),
    false,
  );
});

test("one-hour channels with huddle-like names remain ordinary", () => {
  const ordinary = channel({ name: "design huddle", ttlSeconds: 3_600 });
  assert.equal(isHuddleBackingChannel(ordinary, NONE), false);
  assert.equal(shouldShowSidebarChannel(ordinary, NONE, NONE), true);
});
