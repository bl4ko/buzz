import assert from "node:assert/strict";
import test from "node:test";

import { canRestrictMembers, canRestrictOwner } from "./moderationAccess.ts";

test("community owner and admin may restrict members", () => {
  assert.equal(canRestrictMembers("owner", null), true);
  assert.equal(canRestrictMembers("admin", null), true);
});

test("relay staff without a community role may restrict members", () => {
  assert.equal(canRestrictMembers(undefined, "operator"), true);
  assert.equal(canRestrictMembers(undefined, "moderator"), true);
  assert.equal(canRestrictMembers("member", "moderator"), true);
});

test("plain members and unknown viewers may not restrict members", () => {
  assert.equal(canRestrictMembers("member", null), false);
  assert.equal(canRestrictMembers(undefined, undefined), false);
});

test("only relay staff may restrict an owner", () => {
  assert.equal(canRestrictOwner("operator"), true);
  assert.equal(canRestrictOwner("moderator"), true);
  assert.equal(canRestrictOwner(null), false);
  assert.equal(canRestrictOwner(undefined), false);
});
