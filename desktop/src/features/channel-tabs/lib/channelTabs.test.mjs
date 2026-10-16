import assert from "node:assert/strict";
import { test } from "node:test";

import {
  addTab,
  knownTabs,
  latestChannelTabs,
  moveTab,
  parseChannelTabs,
  removeTab,
  renameTab,
  serializeChannelTabs,
  validateTabValue,
} from "./channelTabs.ts";

const CH = "11111111-1111-4111-8111-111111111111";
const OWNER = "a".repeat(64);
const MEMBER = "b".repeat(64);
const list = (tabs) => JSON.stringify(tabs);

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
    content: list(tabs),
    sig: "",
  };
}

test("parseChannelTabs validates the list", () => {
  assert.equal(
    parseChannelTabs(
      list([
        {
          id: "t1",
          type: "link",
          title: "Grafana",
          value: "https://g.example",
        },
      ]),
    ).length,
    1,
  );
  assert.equal(parseChannelTabs("{}"), null);
  assert.equal(
    parseChannelTabs(
      list([{ id: "bad id", type: "link", title: "A", value: "" }]),
    ),
    null,
  );
  assert.equal(
    parseChannelTabs(
      list([
        { id: "a", type: "link", title: "A", value: "" },
        { id: "a", type: "link", title: "B", value: "" },
      ]),
    ),
    null,
  );
});

test("latestChannelTabs takes the newest stored list from any author", () => {
  const events = [
    tabsEvent("1", OWNER, 10, [
      { id: "a", type: "link", title: "Owner", value: "https://o.example" },
    ]),
    tabsEvent("2", MEMBER, 20, [
      { id: "b", type: "link", title: "Member", value: "https://m.example" },
    ]),
  ];
  const latest = latestChannelTabs(events, CH);
  assert.deepEqual(
    latest.tabs.map((t) => t.title),
    ["Member"],
  );
  assert.equal(latest.eventId, "2");
});

test("knownTabs hides unknown types", () => {
  assert.deepEqual(
    knownTabs([
      { id: "a", type: "future", title: "X", value: "" },
      { id: "b", type: "search", title: "S", value: "CVE" },
    ]).map((t) => t.id),
    ["b"],
  );
});

test("validateTabValue per type", () => {
  assert.equal(validateTabValue("link", "https://grafana.xqx.uk"), null);
  assert.notEqual(validateTabValue("link", "http://grafana.xqx.uk"), null);
  assert.notEqual(validateTabValue("link", "javascript:alert(1)"), null);
  assert.equal(validateTabValue("search", "from:Athene CVE"), null);
  assert.notEqual(validateTabValue("search", " "), null);
  assert.equal(validateTabValue("thread", "a".repeat(64)), null);
  assert.notEqual(validateTabValue("thread", "xyz"), null);
  assert.equal(validateTabValue("canvas", "notes_1"), null);
  assert.notEqual(validateTabValue("canvas", "bad id"), null);
});

test("edit helpers keep order and ids", () => {
  const tabs = [
    { id: "a", type: "link", title: "A", value: "" },
    { id: "b", type: "link", title: "B", value: "" },
  ];
  assert.deepEqual(
    moveTab(tabs, "b", -1).map((t) => t.id),
    ["b", "a"],
  );
  assert.deepEqual(
    moveTab(tabs, "a", -1).map((t) => t.id),
    ["a", "b"],
  );
  assert.equal(renameTab(tabs, "a", "Z")[0].title, "Z");
  assert.deepEqual(
    removeTab(tabs, "a").map((t) => t.id),
    ["b"],
  );
  assert.equal(
    addTab(tabs, { id: "c", type: "search", title: "C", value: "x" }).length,
    3,
  );
  assert.equal(
    serializeChannelTabs([{ ...tabs[0], extra: 1 }]),
    list([tabs[0]]),
  );
});
