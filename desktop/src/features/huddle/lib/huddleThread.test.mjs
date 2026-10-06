import assert from "node:assert/strict";
import test from "node:test";

import {
  huddleChatDestination,
  huddleNotificationQuiet,
  huddleThread,
  huddleTtsScope,
  parseHuddleStartContent,
  sameHuddleNotificationQuiet,
  sameHuddleThreadState,
} from "./huddleThread.ts";

const PARENT = "parent-channel";
const ROOM = "huddle-room";
const ROOT = "a".repeat(64);
const threadState = (overrides = {}) => ({
  phase: "active",
  parent_channel_id: PARENT,
  ephemeral_channel_id: ROOM,
  huddle_thread_event_id: ROOT,
  thread_chat: true,
  ...overrides,
});

test("thread huddles read and speak in the parent-channel thread", () => {
  assert.deepEqual(huddleThread(threadState()), {
    parentChannelId: PARENT,
    rootEventId: ROOT,
  });
  assert.deepEqual(huddleTtsScope(threadState(), ROOM), {
    channelId: PARENT,
    threadRootId: ROOT,
  });
  assert.deepEqual(huddleTtsScope(threadState({ phase: "connected" }), ROOM), {
    channelId: PARENT,
    threadRootId: ROOT,
  });
});

test("legacy huddles keep chat and speech in the ephemeral channel", () => {
  const legacy = threadState({ thread_chat: false });
  assert.equal(huddleThread(legacy), null);
  assert.deepEqual(huddleTtsScope(legacy, ROOM), {
    channelId: ROOM,
    threadRootId: null,
  });
});

test("speech waits for a connected session that matches the local room", () => {
  assert.equal(huddleTtsScope(threadState(), null), null);
  assert.equal(huddleTtsScope(null, ROOM), null);
  assert.equal(huddleTtsScope(threadState(), "other-room"), null);
  for (const phase of ["idle", "creating", "connecting", "leaving"]) {
    assert.equal(huddleTtsScope(threadState({ phase }), ROOM), null, phase);
  }
  assert.equal(
    huddleTtsScope(threadState({ huddle_thread_event_id: null }), ROOM),
    null,
    "a thread huddle never falls back to speaking the backing channel",
  );
});

test("start events declare thread chat explicitly", () => {
  assert.deepEqual(
    parseHuddleStartContent(
      JSON.stringify({ ephemeral_channel_id: ROOM, chat: "thread" }),
    ),
    { ephemeralChannelId: ROOM, threadChat: true },
  );
  assert.deepEqual(
    parseHuddleStartContent(JSON.stringify({ ephemeral_channel_id: ROOM })),
    { ephemeralChannelId: ROOM, threadChat: false },
  );
  assert.deepEqual(parseHuddleStartContent("not json"), {
    ephemeralChannelId: null,
    threadChat: false,
  });
});

test("the live huddle thread is quiet only while the huddle runs", () => {
  const quiet = huddleNotificationQuiet(
    threadState({ agent_pubkeys: ["AGENT"] }),
  );
  assert.deepEqual([...quiet.quietRootIds], [ROOT]);
  assert.deepEqual([...quiet.quietAuthorPubkeys], ["agent"]);
  for (const state of [
    threadState({ phase: "leaving" }),
    threadState({ phase: "idle" }),
    threadState({ thread_chat: false }),
    null,
  ]) {
    assert.equal(huddleNotificationQuiet(state).quietRootIds.size, 0);
  }
  assert.equal(
    sameHuddleNotificationQuiet(
      quiet,
      huddleNotificationQuiet(threadState({ agent_pubkeys: ["agent"] })),
    ),
    true,
  );
  assert.equal(
    sameHuddleNotificationQuiet(
      quiet,
      huddleNotificationQuiet(threadState({ agent_pubkeys: [] })),
    ),
    false,
  );
});

test("unrelated backend state changes keep the thread state", () => {
  assert.equal(
    sameHuddleThreadState(
      threadState(),
      threadState({ agent_pubkeys: ["agent"] }),
    ),
    true,
  );
  assert.equal(
    sameHuddleThreadState(threadState(), threadState({ phase: "connected" })),
    false,
  );
});

test("the huddle window opens the thread, or the backing channel for old huddles", () => {
  assert.deepEqual(huddleChatDestination(threadState(), ROOM), {
    channelId: PARENT,
    threadRootId: ROOT,
  });
  assert.deepEqual(
    huddleChatDestination(threadState({ thread_chat: false }), "window-room"),
    { channelId: ROOM, threadRootId: null },
  );
  assert.deepEqual(
    huddleChatDestination(
      threadState({ thread_chat: false, ephemeral_channel_id: null }),
      "window-room",
    ),
    { channelId: "window-room", threadRootId: null },
  );
  assert.equal(huddleChatDestination(null, null), null);
});
