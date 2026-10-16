import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { act } from "react";

import { createEventTransport, createHookHarness } from "./hookHarness.mjs";
import { useChannelTabs } from "./useChannelTabs.ts";

const CH = "11111111-1111-4111-8111-111111111111";
const OWNER = "a".repeat(64);
const MEMBER = "b".repeat(64);
const canEdit = (pubkey) => pubkey === OWNER || pubkey === "f".repeat(64);

function tabsEvent(id, pubkey, createdAt, tabs) {
  return {
    id,
    pubkey,
    created_at: createdAt,
    kind: 30321,
    tags: [
      ["d", CH],
      ["h", CH],
    ],
    content: JSON.stringify(tabs),
    sig: "",
  };
}

const h = createHookHarness((transport) =>
  useChannelTabs(CH, canEdit, transport),
);
afterEach(() => h.unmount());

test("only lists from allowed editors count and unknown types stay hidden", async () => {
  const transport = createEventTransport([
    tabsEvent("1", OWNER, 10, [
      { id: "a", type: "link", title: "Grafana", value: "https://g.example" },
      { id: "z", type: "future", title: "Z", value: "" },
    ]),
    tabsEvent("2", MEMBER, 20, [
      { id: "b", type: "link", title: "Spam", value: "https://s.example" },
    ]),
  ]);
  await h.mount(transport);
  await h.waitFor(() => h.latest?.tabs.length === 2);
  assert.deepEqual(transport.fetched[0].kinds, [30321]);
  assert.deepEqual(
    h.latest.visible.map((t) => t.title),
    ["Grafana"],
  );
});

test("save publishes the whole ordered list after the current one", async () => {
  const transport = createEventTransport([
    tabsEvent("1", OWNER, 10, [
      { id: "a", type: "link", title: "Grafana", value: "https://g.example" },
    ]),
  ]);
  await h.mount(transport);
  await h.waitFor(() => h.latest?.tabs.length === 1);
  await act(async () =>
    h.latest.save([
      ...h.latest.tabs,
      { id: "c", type: "search", title: "CVE", value: "from:Athene CVE" },
    ]),
  );
  assert.equal(transport.signed[0].kind, 30321);
  assert.equal(transport.signed[0].createdAt, 11);
  assert.deepEqual(transport.signed[0].tags, [
    ["d", CH],
    ["h", CH],
  ]);
  assert.deepEqual(
    JSON.parse(transport.signed[0].content).map((t) => t.id),
    ["a", "c"],
  );
  await h.waitFor(() => h.latest.tabs.length === 2);
});
