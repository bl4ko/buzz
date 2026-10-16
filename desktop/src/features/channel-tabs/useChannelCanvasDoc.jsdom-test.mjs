import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { act } from "react";

import { createEventTransport, createHookHarness } from "./hookHarness.mjs";
import { useChannelCanvasDoc } from "./useChannelCanvasDoc.ts";

const CH = "11111111-1111-4111-8111-111111111111";

function doc(id, pubkey, createdAt, content) {
  return {
    id,
    pubkey,
    created_at: createdAt,
    kind: 30322,
    tags: [
      ["d", `${CH}:notes`],
      ["h", CH],
    ],
    content,
    sig: "",
  };
}

const h = createHookHarness((transport) =>
  useChannelCanvasDoc(CH, "notes", transport),
);
afterEach(() => h.unmount());

test("save refuses a stale base unless forced", async () => {
  const transport = createEventTransport([
    doc("2", "b".repeat(64), 20, "theirs"),
  ]);
  await h.mount(transport);
  await h.waitFor(() => h.latest?.latest?.eventId === "2");
  assert.deepEqual(transport.fetched[0]["#d"], [`${CH}:notes`]);
  let result;
  await act(async () => {
    result = await h.latest.save("mine", "1");
  });
  assert.equal(result, "conflict");
  assert.equal(transport.published.length, 0);
  await act(async () => {
    result = await h.latest.save("mine", "1", true);
  });
  assert.equal(result, "saved");
  assert.equal(transport.signed[0].createdAt, 21);
  assert.deepEqual(transport.signed[0].tags, [
    ["d", `${CH}:notes`],
    ["h", CH],
  ]);
});

test("save rejects content over 64 KB", async () => {
  const transport = createEventTransport([]);
  await h.mount(transport);
  await h.waitFor(() => h.latest && !h.latest.isLoading);
  await assert.rejects(() => h.latest.save("x".repeat(65_537), null), /64 KB/);
});
