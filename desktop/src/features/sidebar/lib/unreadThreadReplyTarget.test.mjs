import assert from "node:assert/strict";
import test from "node:test";

import {
  clearThreadUnreadOverrides,
  getChannelUnreadThreadFeedItems,
  getUnreadThreadReplyTarget,
} from "./unreadThreadReplyTarget.ts";

function reply(id, rootId, createdAt, channelId = "c1") {
  return {
    category: "activity",
    channelId,
    content: id,
    createdAt,
    id,
    kind: 9,
    pubkey: "a".repeat(64),
    tags: [
      ["e", rootId, "", "root"],
      ["e", rootId, "", "reply"],
    ],
  };
}

const items = [
  reply("r3", "rootB", 300),
  reply("r1", "rootA", 100),
  reply("r2", "rootA", 200),
];

test("getUnreadThreadReplyTarget_topLevelUnread_keepsTopLevelJump", () => {
  assert.equal(
    getUnreadThreadReplyTarget({
      channelReadAt: 50,
      hasTopLevelUnread: true,
      items,
    }),
    null,
  );
});

test("getUnreadThreadReplyTarget_threadRepliesOnly_targetsOldestReply", () => {
  assert.deepEqual(
    getUnreadThreadReplyTarget({
      channelReadAt: 50,
      hasTopLevelUnread: false,
      items,
    }),
    { itemIds: ["r1", "r2"], messageId: "r1", threadRootId: "rootA" },
  );
});

test("getUnreadThreadReplyTarget_noUnread_staysAtBottom", () => {
  assert.equal(
    getUnreadThreadReplyTarget({
      channelReadAt: 50,
      hasTopLevelUnread: false,
      items: [],
    }),
    null,
  );
});

test("getUnreadThreadReplyTarget_neverReadChannel_staysAtBottom", () => {
  assert.equal(
    getUnreadThreadReplyTarget({
      channelReadAt: null,
      hasTopLevelUnread: false,
      items,
    }),
    null,
  );
});

test("getChannelUnreadThreadFeedItems_filtersToChannel", () => {
  const other = reply("x1", "rootX", 10, "c2");
  assert.deepEqual(getChannelUnreadThreadFeedItems([...items, other], "c2"), [
    other,
  ]);
});

test("clearThreadUnreadOverrides_lastChannelOverride_clearsInboxSource", () => {
  const undone = [];
  const cleared = [];
  const clear = (locallyUnreadFeedItems) =>
    clearThreadUnreadOverrides({
      channelId: "c1",
      clearChannelUnreadSource: (channelId, source) =>
        cleared.push([channelId, source]),
      itemIds: ["r1", "r2"],
      locallyUnreadFeedItems,
      undoUnread: (id) => undone.push(id),
    });

  clear([items[1], items[0]]);
  assert.deepEqual(undone, ["r1", "r2"]);
  assert.deepEqual(cleared, []);

  clear([items[1]]);
  assert.deepEqual(cleared, [["c1", "inbox"]]);
});
