import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import * as React from "react";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";

import { useChannelPins } from "./useChannelPins.ts";

const CHANNEL = "channel-1";
const ALICE = "a".repeat(64);
const BOB = "b".repeat(64);

function pin(id, target, createdAt, status = "pinned", pubkey = ALICE) {
  return {
    id,
    pubkey,
    created_at: createdAt,
    kind: 40004,
    tags: [
      ["h", CHANNEL],
      ["e", target],
      ["status", status],
    ],
    content: "",
    sig: "",
  };
}

function message(id, content, pubkey = BOB, channel = CHANNEL) {
  return {
    id,
    pubkey,
    created_at: 10,
    kind: 9,
    tags: [["h", channel]],
    content,
    sig: "",
  };
}

function createTransport({ pins, messages, edits = [] }) {
  const transport = {
    live: null,
    liveFilter: null,
    signed: [],
    published: [],
    nowSeconds: 1_000,
    async fetchEvents(filter) {
      if (filter.ids) {
        return messages.filter((event) => filter.ids.includes(event.id));
      }
      if (filter.kinds.includes(40003)) {
        return edits.filter((edit) =>
          edit.tags.some(
            (tag) => tag[0] === "e" && filter["#e"].includes(tag[1]),
          ),
        );
      }
      assert.deepEqual(filter.kinds, [40004]);
      assert.deepEqual(filter["#h"], [CHANNEL]);
      return pins;
    },
    async subscribeLive(filter, onEvent) {
      transport.liveFilter = filter;
      transport.live = onEvent;
      return () => {
        transport.live = null;
      };
    },
    subscribeToReconnects() {
      return () => {};
    },
    async signEvent(input) {
      transport.signed.push(input);
      return {
        id: `signed-${transport.signed.length}`,
        pubkey: ALICE,
        created_at: input.createdAt,
        kind: input.kind,
        tags: input.tags,
        content: input.content,
        sig: "",
      };
    },
    async publishEvent(event) {
      transport.published.push(event);
      return event;
    },
    now() {
      return transport.nowSeconds;
    },
  };
  return transport;
}

let root;
let container;
let latest;

function Probe({ transport }) {
  latest = useChannelPins(CHANNEL, transport);
  return null;
}

async function mount(transport) {
  container = document.createElement("div");
  document.body.appendChild(container);
  root = createRoot(container);
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  await act(async () => {
    root.render(
      React.createElement(
        QueryClientProvider,
        { client: queryClient },
        React.createElement(Probe, { transport }),
      ),
    );
  });
}

async function waitFor(predicate) {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    if (predicate()) return;
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 5));
    });
  }
  assert.fail("condition was not reached");
}

function pinnedIds() {
  return latest?.pinnedMessages.map((item) => item.target.id) ?? [];
}

afterEach(async () => {
  await act(async () => {
    root?.unmount();
  });
  container?.remove();
  latest = undefined;
});

test("loads current pins, skips unloadable targets, and applies edits", async () => {
  const transport = createTransport({
    pins: [
      pin("p1", "m1", 100),
      pin("p2", "m2", 200),
      pin("p3", "m2", 300, "unpinned"),
      pin("p4", "missing", 400),
      pin("p5", "other-channel", 500),
      pin("p6", "m3", 150),
    ],
    messages: [
      message("m1", "first"),
      message("m2", "second"),
      message("m3", "third"),
      message("other-channel", "elsewhere", BOB, "channel-2"),
    ],
    edits: [
      {
        ...message("edit-1", "first, edited"),
        kind: 40003,
        created_at: 20,
        tags: [
          ["h", CHANNEL],
          ["e", "m1"],
        ],
      },
      {
        ...message("edit-2", "forged", ALICE),
        kind: 40003,
        created_at: 30,
        tags: [
          ["h", CHANNEL],
          ["e", "m3"],
        ],
      },
    ],
  });
  await mount(transport);
  await waitFor(() => pinnedIds().length === 2);

  assert.deepEqual(pinnedIds(), ["m3", "m1"]);
  assert.equal(latest.pinnedMessages[1].target.content, "first, edited");
  assert.equal(latest.pinnedMessages[0].target.content, "third");
  assert.equal(latest.isPinned("m1"), true);
  assert.equal(latest.isPinned("m2"), false);
  assert.deepEqual(transport.liveFilter.kinds, [40004, 5, 9005]);
  assert.deepEqual(transport.liveFilter["#h"], [CHANNEL]);
});

test("live pin, unpin, and deletion events update state", async () => {
  const transport = createTransport({
    pins: [pin("p1", "m1", 100)],
    messages: [message("m1", "first"), message("m2", "second")],
  });
  await mount(transport);
  await waitFor(() => pinnedIds().length === 1 && transport.live !== null);

  await act(async () => {
    transport.live(pin("p2", "m2", 200));
  });
  await waitFor(() => pinnedIds().length === 2);
  assert.deepEqual(pinnedIds(), ["m2", "m1"]);

  await act(async () => {
    transport.live(pin("p3", "m1", 300, "unpinned", BOB));
  });
  await waitFor(() => pinnedIds().length === 1);
  assert.deepEqual(pinnedIds(), ["m2"]);

  await act(async () => {
    transport.live({
      ...message("del-1", ""),
      kind: 9005,
      tags: [
        ["h", CHANNEL],
        ["e", "m2"],
      ],
    });
  });
  await waitFor(() => pinnedIds().length === 0);
  assert.equal(latest.isPinned("m2"), false);
});

test("setPinned signs the exact event shape and updates state", async () => {
  const transport = createTransport({
    pins: [pin("p1", "m1", 1_000)],
    messages: [message("m1", "first"), message("m2", "second")],
  });
  await mount(transport);
  await waitFor(() => pinnedIds().length === 1);

  await act(async () => {
    await latest.setPinned("m1", false);
  });
  assert.deepEqual(transport.signed[0], {
    kind: 40004,
    content: "",
    createdAt: 1_001,
    tags: [
      ["h", CHANNEL],
      ["e", "m1"],
      ["status", "unpinned"],
    ],
  });
  assert.equal(transport.published.length, 1);
  await waitFor(() => pinnedIds().length === 0);

  await act(async () => {
    await latest.setPinned("m2", true);
  });
  assert.equal(transport.signed[1].createdAt, 1_000);
  assert.deepEqual(transport.signed[1].tags, [
    ["h", CHANNEL],
    ["e", "m2"],
    ["status", "pinned"],
  ]);
  await waitFor(() => pinnedIds().length === 1);
  assert.deepEqual(pinnedIds(), ["m2"]);
});
