import assert from "node:assert/strict";
import { test } from "node:test";

import { extractFilesAndLinks, filterFilesAndLinks } from "./filesAndLinks.ts";

function message(id, content, tags = [], createdAt = 10) {
  return {
    id,
    pubkey: "a".repeat(64),
    created_at: createdAt,
    kind: 9,
    tags: [["h", "c"], ...tags],
    content,
    sig: "",
  };
}

test("extractFilesAndLinks classifies media, files, and links", () => {
  const items = extractFilesAndLinks([
    message("m1", "see https://grafana.xqx.uk/d/abc?x=1).", [], 30),
    message(
      "m2",
      "photo https://buzz.example/media/p.png",
      [["imeta", "url https://buzz.example/media/p.png", "m image/png"]],
      20,
    ),
    message(
      "m3",
      "report",
      [
        [
          "imeta",
          "url https://buzz.example/media/r.pdf",
          "m application/pdf",
          "filename report.pdf",
        ],
      ],
      10,
    ),
  ]);
  assert.deepEqual(
    items.map((i) => [i.kind, i.messageId]),
    [
      ["link", "m1"],
      ["media", "m2"],
      ["file", "m3"],
    ],
  );
  assert.equal(items[0].url, "https://grafana.xqx.uk/d/abc?x=1");
  assert.equal(items[0].host, "grafana.xqx.uk");
  assert.equal(items[0].path, "/d/abc");
  assert.equal(items[2].name, "report.pdf");
});

test("filterFilesAndLinks filters by kind and search text", () => {
  const items = extractFilesAndLinks([
    message("m1", "https://grafana.xqx.uk/d/abc"),
    message("m2", "x", [
      ["imeta", "url https://b.example/r.pdf", "m application/pdf"],
    ]),
  ]);
  assert.deepEqual(
    filterFilesAndLinks(items, "links", "").map((i) => i.messageId),
    ["m1"],
  );
  assert.deepEqual(
    filterFilesAndLinks(items, "files", "").map((i) => i.messageId),
    ["m2"],
  );
  assert.deepEqual(
    filterFilesAndLinks(items, "all", "GRAFANA").map((i) => i.messageId),
    ["m1"],
  );
  assert.deepEqual(filterFilesAndLinks(items, "media", ""), []);
});
