import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { act } from "react";

import { createHookHarness } from "./hookHarness.mjs";
import { useChannelFilesAndLinks } from "./useChannelFilesAndLinks.ts";

const CH = "11111111-1111-4111-8111-111111111111";
const h = createHookHarness((fetchPage) =>
  useChannelFilesAndLinks(CH, fetchPage),
);
afterEach(() => h.unmount());

test("pages older results with until", async () => {
  const calls = [];
  const page = Array.from({ length: 100 }, (_, i) => ({
    id: `m${i}`,
    pubkey: "a".repeat(64),
    created_at: 1000 - i,
    kind: 9,
    tags: [["h", CH]],
    content: `https://x.example/${i}`,
    sig: "",
  }));
  const fetchPage = async (channelId, until) => {
    calls.push([channelId, until]);
    return until === undefined ? page : [];
  };
  await h.mount(fetchPage);
  await h.waitFor(() => h.latest?.items.length === 100);
  assert.equal(h.latest.hasMore, true);
  await act(async () => h.latest.loadMore());
  assert.deepEqual(calls[1], [CH, 901]);
});

test("a full page sharing one second still moves the cursor back", async () => {
  const calls = [];
  const sameSecond = (prefix) =>
    Array.from({ length: 100 }, (_, i) => ({
      id: `${prefix}${i}`,
      pubkey: "a".repeat(64),
      created_at: 1000,
      kind: 9,
      tags: [["h", CH]],
      content: `https://x.example/${prefix}${i}`,
      sig: "",
    }));
  const fetchPage = async (channelId, until) => {
    calls.push([channelId, until]);
    return sameSecond(until === undefined ? "a" : "b");
  };
  await h.mount(fetchPage);
  await h.waitFor(() => h.latest?.items.length === 100);
  await act(async () => h.latest.loadMore());
  await h.waitFor(() => calls.length === 2);
  await act(async () => h.latest.loadMore());
  await h.waitFor(() => calls.length === 3);
  assert.deepEqual(
    calls.map((call) => call[1]),
    [undefined, 1000, 999],
  );
});
