import assert from "node:assert/strict";
import { test } from "node:test";

import { taskPermissions } from "./useTaskPermissions.ts";

const OWNER = "a".repeat(64);
const ADMIN = "b".repeat(64);
const AGENT = "c".repeat(64);
const GUEST = "d".repeat(64);
const relayMembers = [{ pubkey: OWNER, role: "owner" }];
const channelMembers = [
  { pubkey: ADMIN, role: "admin" },
  { pubkey: AGENT, role: "bot" },
  { pubkey: GUEST, role: "guest" },
];

test("owner can do everything, admin edits tabs, guest edits nothing", () => {
  const owner = taskPermissions({
    relayMembers,
    channelMembers,
    currentPubkey: OWNER,
  });
  assert.deepEqual(
    [owner.canSetStatus, owner.canEditTabs, owner.canEditCanvas],
    [true, true, true],
  );
  const admin = taskPermissions({
    relayMembers,
    channelMembers,
    currentPubkey: ADMIN,
  });
  assert.deepEqual(
    [admin.canSetStatus, admin.canEditTabs, admin.canEditCanvas],
    [false, true, true],
  );
  const guest = taskPermissions({
    relayMembers,
    channelMembers,
    currentPubkey: GUEST,
  });
  assert.deepEqual(
    [guest.canSetStatus, guest.canEditTabs, guest.canEditCanvas],
    [false, false, false],
  );
  assert.equal(owner.canEditTabsFor(ADMIN), true);
  assert.equal(owner.canEditTabsFor(AGENT), false);
  const channelOwner = taskPermissions({
    relayMembers,
    channelMembers: [...channelMembers, { pubkey: GUEST, role: "owner" }],
    currentPubkey: GUEST,
  });
  assert.equal(channelOwner.canSetStatus, false);
  assert.equal(channelOwner.canEditTabs, true);
});
