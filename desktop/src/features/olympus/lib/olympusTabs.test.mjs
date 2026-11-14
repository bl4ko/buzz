import assert from "node:assert/strict";
import test from "node:test";

import { parseOlympusTab, visibleOlympusTabs } from "./olympusTabs.ts";

const ids = (tabs) => tabs.map((tab) => tab.id);

test("the On this Mac tab shows only when local agents exist", () => {
  assert.equal(
    ids(visibleOlympusTabs("agents", false)).includes("local"),
    false,
  );
  assert.equal(ids(visibleOlympusTabs("agents", true)).at(-1), "local");
  assert.equal(ids(visibleOlympusTabs("local", false)).at(-1), "local");
  assert.equal(parseOlympusTab("local"), "local");
  assert.equal(parseOlympusTab("nope"), "agents");
});
