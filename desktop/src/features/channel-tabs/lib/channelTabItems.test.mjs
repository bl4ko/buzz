import assert from "node:assert/strict";
import { test } from "node:test";

import { buildChannelTabItems, resolveSelectedTab } from "./channelTabItems.ts";

const custom = [
  { id: "g", type: "link", title: "Grafana", value: "https://g.example" },
];

test("built-in tabs show only with content, messages always", () => {
  assert.deepEqual(
    buildChannelTabItems({
      taskCount: 0,
      awaitingCount: 0,
      pinCount: 0,
      fileCount: 0,
      customTabs: [],
    }).map((i) => i.key),
    ["messages"],
  );
  const items = buildChannelTabItems({
    taskCount: 3,
    awaitingCount: 2,
    pinCount: 1,
    fileCount: 4,
    customTabs: custom,
  });
  assert.deepEqual(
    items.map((i) => i.key),
    ["messages", "tasks", "pins", "files", "custom:g"],
  );
  assert.deepEqual(
    items.map((i) => i.label),
    ["Messages", "Tasks", "Pins", "Files and links", "Grafana"],
  );
  assert.equal(items[1].badge, 2);
  assert.equal(
    buildChannelTabItems({
      taskCount: 1,
      awaitingCount: 0,
      pinCount: 0,
      fileCount: 0,
      customTabs: [],
    })[1].badge,
    undefined,
  );
});

test("a vanished tab falls back to messages", () => {
  const items = buildChannelTabItems({
    taskCount: 0,
    awaitingCount: 0,
    pinCount: 0,
    fileCount: 0,
    customTabs: [],
  });
  assert.equal(resolveSelectedTab(items, "tasks"), "messages");
  assert.equal(resolveSelectedTab(items, "messages"), "messages");
});
