import assert from "node:assert/strict";
import test from "node:test";

import {
  canDeleteMessageForCurrentUser,
  canManageMessageForCurrentUser,
} from "./canManageMessage.ts";
import {
  KIND_HUDDLE_STARTED,
  KIND_STREAM_MESSAGE,
} from "@/shared/constants/kinds";

const currentPubkey = "a".repeat(64);
const ownedAgent = "b".repeat(64);
const otherPubkey = "c".repeat(64);
const otherAgent = "d".repeat(64);
const profiles = {
  [ownedAgent]: { isAgent: true, ownerPubkey: currentPubkey },
  [otherAgent]: { isAgent: true, ownerPubkey: otherPubkey },
};

for (const kind of [KIND_STREAM_MESSAGE, KIND_HUDDLE_STARTED]) {
  for (const [pubkey, expected] of [
    [currentPubkey, true],
    [currentPubkey.toUpperCase(), true],
    [ownedAgent, true],
    [otherPubkey, false],
    [otherAgent, false],
    [undefined, false],
  ]) {
    test(`kind ${kind} deletion permission for ${pubkey}`, () => {
      const message = { kind, pubkey };
      assert.equal(
        canDeleteMessageForCurrentUser(message, currentPubkey, profiles),
        expected,
      );
      assert.equal(
        canManageMessageForCurrentUser(message, currentPubkey, profiles),
        expected && kind !== KIND_HUDDLE_STARTED,
      );
      assert.equal(
        canDeleteMessageForCurrentUser(message, undefined, profiles),
        false,
      );
    });
  }
}

test("agent deletion requires an ownership record", () => {
  assert.equal(
    canDeleteMessageForCurrentUser(
      { kind: KIND_HUDDLE_STARTED, pubkey: ownedAgent },
      currentPubkey,
      undefined,
    ),
    false,
  );
});
