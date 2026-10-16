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
