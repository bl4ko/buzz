import assert from "node:assert/strict";
import test from "node:test";

import {
  canDeleteMessageForCurrentUser,
  canManageMessageForCurrentUser,
  canModerateChannelMessages,
} from "./canManageMessage.ts";
import {
  KIND_FORUM_COMMENT,
  KIND_FORUM_POST,
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

for (const role of ["owner", "admin", "member", undefined]) {
  for (const kind of [
    KIND_STREAM_MESSAGE,
    KIND_HUDDLE_STARTED,
    KIND_FORUM_POST,
    KIND_FORUM_COMMENT,
  ]) {
    test(`community ${role} deletion of another author's kind ${kind}`, () => {
      const canModerate = canModerateChannelMessages(currentPubkey, [], role);
      assert.equal(canModerate, role === "owner" || role === "admin");
      const message = { kind, pubkey: otherPubkey };
      assert.equal(
        canDeleteMessageForCurrentUser(
          message,
          currentPubkey,
          profiles,
          canModerate,
        ),
        canModerate,
      );
      assert.equal(
        canManageMessageForCurrentUser(message, currentPubkey, profiles),
        false,
      );
      assert.equal(
        canDeleteMessageForCurrentUser(message, undefined, profiles, true),
        false,
      );
    });
  }
}

for (const role of ["owner", "admin", "member", "guest", "bot"]) {
  test(`channel ${role} deletion permission is scoped to the current member`, () => {
    assert.equal(
      canModerateChannelMessages(
        currentPubkey,
        [{ pubkey: currentPubkey.toUpperCase(), role }],
        "member",
      ),
      role === "owner" || role === "admin",
    );
    assert.equal(
      canModerateChannelMessages(
        currentPubkey,
        [{ pubkey: otherPubkey, role }],
        "member",
      ),
      false,
    );
    assert.equal(
      canModerateChannelMessages(
        undefined,
        [{ pubkey: currentPubkey, role }],
        "owner",
      ),
      false,
    );
  });
}
