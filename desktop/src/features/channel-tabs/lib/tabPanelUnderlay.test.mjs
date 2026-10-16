import assert from "node:assert/strict";
import { test } from "node:test";

import { tabPanelUnderlay } from "./tabPanelUnderlay.ts";

test("an open tab panel hides and disables the timeline underneath", () => {
  assert.deepEqual(tabPanelUnderlay(true), {
    className: "contents invisible",
    inert: true,
  });
});

test("without a tab panel the timeline stays interactive", () => {
  assert.deepEqual(tabPanelUnderlay(false), {
    className: "contents",
    inert: undefined,
  });
});
