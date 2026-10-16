import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import * as React from "react";
import { act } from "react";
import { createRoot } from "react-dom/client";

import { extractFilesAndLinks } from "../lib/filesAndLinks.ts";
import { ChannelFilesTab } from "./ChannelFilesTab.tsx";

const message = (id, content, tags = [], createdAt = 10) => ({
  id,
  pubkey: "a".repeat(64),
  created_at: createdAt,
  kind: 9,
  tags: [["h", "c"], ...tags],
  content,
  sig: "",
});
const media = Array.from({ length: 10 }, (_, i) =>
  message(
    `p${i}`,
    "",
    [["imeta", `url https://cdn.example/p${i}.png`, "m image/png"]],
    100 - i,
  ),
);
const items = extractFilesAndLinks([
  ...media,
  message("l1", "https://grafana.xqx.uk/d/abc", [], 50),
  message(
    "f1",
    "",
    [
      [
        "imeta",
        "url https://cdn.example/r.pdf",
        "m application/pdf",
        "filename report.pdf",
      ],
    ],
    40,
  ),
]);

let root;
let container;
let opened;

async function render() {
  opened = [];
  container = document.createElement("div");
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () =>
    root.render(
      React.createElement(ChannelFilesTab, {
        files: { items, isLoading: false, hasMore: false, loadMore: () => {} },
        onOpenMessage: (item) => opened.push(item.messageId),
      }),
    ),
  );
}

afterEach(async () => {
  await act(async () => root.unmount());
  container.remove();
});

const all = (id) => [...container.querySelectorAll(`[data-testid="${id}"]`)];

test("shows a media grid with See all and rows for files and links", async () => {
  await render();
  assert.equal(all("files-media-item").length, 8);
  assert.deepEqual(
    all("files-row").map((row) => row.dataset.kind),
    ["link", "file"],
  );
  assert.match(all("files-row")[0].textContent, /grafana\.xqx\.uk/);
  assert.match(all("files-row")[0].textContent, /\/d\/abc/);
  await act(async () => all("files-see-all")[0].click());
  assert.equal(all("files-media-item").length, 10);
  assert.equal(all("files-row").length, 0);
});

test("filters and search narrow the list, rows open their message", async () => {
  await render();
  await act(async () => all("files-filter-links")[0].click());
  assert.equal(all("files-media-item").length, 0);
  assert.deepEqual(
    all("files-row").map((row) => row.dataset.kind),
    ["link"],
  );
  await act(async () => all("files-filter-all")[0].click());
  const input = all("files-search")[0];
  await act(async () => {
    const setter = Object.getOwnPropertyDescriptor(
      window.HTMLInputElement.prototype,
      "value",
    ).set;
    setter.call(input, "report");
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  assert.deepEqual(
    all("files-row").map((row) => row.dataset.kind),
    ["file"],
  );
  await act(async () => all("files-row")[0].click());
  assert.deepEqual(opened, ["f1"]);
});

test("a video without a thumbnail shows a play placeholder, not an image", async () => {
  const video = extractFilesAndLinks([
    message(
      "v1",
      "",
      [["imeta", "url https://cdn.example/v.mp4", "m video/mp4"]],
      200,
    ),
  ]);
  opened = [];
  container = document.createElement("div");
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () =>
    root.render(
      React.createElement(ChannelFilesTab, {
        files: {
          items: video,
          isLoading: false,
          hasMore: false,
          loadMore: () => {},
        },
        onOpenMessage: () => {},
      }),
    ),
  );
  assert.equal(all("files-video-placeholder").length, 1);
  assert.equal(container.querySelector("img"), null);
});
