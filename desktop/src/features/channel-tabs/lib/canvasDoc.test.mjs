import assert from "node:assert/strict";
import { test } from "node:test";

import {
  canvasByteLength,
  canvasConflict,
  canvasDTag,
  canvasTags,
  latestCanvas,
} from "./canvasDoc.ts";

const CH = "11111111-1111-4111-8111-111111111111";

function doc(id, pubkey, createdAt, content, canvas = "notes") {
  return {
    id,
    pubkey,
    created_at: createdAt,
    kind: 30322,
    tags: [
      ["d", `${CH}:${canvas}`],
      ["h", CH],
    ],
    content,
    sig: "",
  };
}

test("latestCanvas picks newest, then lower id", () => {
  assert.equal(
    latestCanvas(
      [doc("2", "a", 10, "x"), doc("1", "b", 10, "y"), doc("0", "c", 5, "z")],
      CH,
      "notes",
    ).eventId,
    "1",
  );
  assert.equal(
    latestCanvas([doc("1", "a", 10, "x", "other")], CH, "notes"),
    null,
  );
});

test("canvas conflict blocks silent overwrite", () => {
  const latest = latestCanvas([doc("2", "b", 20, "theirs")], CH, "notes");
  assert.equal(canvasConflict("1", latest)?.author, "b");
  assert.equal(canvasConflict("2", latest), null);
  assert.equal(canvasConflict(null, null), null);
});

test("canvas helpers", () => {
  assert.equal(canvasDTag(CH, "notes"), `${CH}:notes`);
  assert.deepEqual(canvasTags(CH, "notes"), [
    ["d", `${CH}:notes`],
    ["h", CH],
  ]);
  assert.equal(canvasByteLength("é"), 2);
});
