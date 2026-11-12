import assert from "node:assert/strict";
import test from "node:test";

import {
  hasDerivedCommunityName,
  relayCommunityName,
} from "./relayCommunityName.ts";

const community = (name) => ({
  id: "c1",
  name,
  relayUrl: "wss://buzz.bl4ko.com",
  addedAt: "2026-11-12T00:00:00.000Z",
});

test("only a host-derived community name follows the relay", () => {
  assert.equal(hasDerivedCommunityName(community("buzz")), true);
  assert.equal(hasDerivedCommunityName(community("Olympus")), false);
  assert.equal(hasDerivedCommunityName(community("Team")), false);
});

test("the relay name replaces it unless it is unset or the upstream default", () => {
  assert.equal(relayCommunityName("  Olympus "), "Olympus");
  assert.equal(relayCommunityName("Buzz Relay"), null);
  assert.equal(relayCommunityName(""), null);
  assert.equal(relayCommunityName(null), null);
  assert.equal(relayCommunityName("x".repeat(65)), null);
});
