import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import * as React from "react";
import { act } from "react";
import { createRoot } from "react-dom/client";

import { ChannelTabBar } from "./ChannelTabBar.tsx";

let root;
let container;

async function render(props) {
  container = document.createElement("div");
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () => root.render(React.createElement(ChannelTabBar, props)));
}

afterEach(async () => {
  await act(async () => root.unmount());
  container.remove();
});

const noop = () => {};
const items = [
  { key: "messages", label: "Messages" },
  { key: "tasks", label: "Tasks", badge: 2 },
  {
    key: "custom:g",
    label: "Grafana",
    custom: {
      id: "g",
      type: "link",
      title: "Grafana",
      value: "https://g.example",
    },
  },
];

test("renders tabs, badge, selection, and selection changes", async () => {
  const selected = [];
  await render({
    items,
    selected: "tasks",
    onSelect: (key) => selected.push(key),
    canEdit: false,
    onAdd: noop,
    onEdit: noop,
    onMove: noop,
    onRemove: noop,
  });
  assert.equal(
    container.querySelector('[data-testid="channel-tab-badge-tasks"]')
      .textContent,
    "2",
  );
  assert.equal(
    container
      .querySelector('[data-testid="channel-tab-tasks"]')
      .getAttribute("aria-selected"),
    "true",
  );
  assert.equal(
    container.querySelector('[data-testid="channel-tab-add"]'),
    null,
  );
  await act(async () =>
    container.querySelector('[data-testid="channel-tab-custom:g"]').click(),
  );
  assert.deepEqual(selected, ["custom:g"]);
});

test("editors get the add button", async () => {
  let added = 0;
  await render({
    items,
    selected: "messages",
    onSelect: noop,
    canEdit: true,
    onAdd: () => {
      added += 1;
    },
    onEdit: noop,
    onMove: noop,
    onRemove: noop,
  });
  await act(async () =>
    container.querySelector('[data-testid="channel-tab-add"]').click(),
  );
  assert.equal(added, 1);
});
