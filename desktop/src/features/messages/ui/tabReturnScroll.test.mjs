import assert from "node:assert/strict";
import { test } from "node:test";

import { isTabPanelTarget, shouldReturnToTail } from "./tabReturnScroll.ts";

test("returning to Messages scrolls when stuck to the bottom or messages arrived", () => {
  assert.equal(
    shouldReturnToTail({ wasAtBottom: true, hasUnseen: false }),
    true,
  );
  assert.equal(
    shouldReturnToTail({ wasAtBottom: false, hasUnseen: true }),
    true,
  );
  assert.equal(
    shouldReturnToTail({ wasAtBottom: false, hasUnseen: false }),
    false,
  );
});

test("targets outside the DOM are not tab panel targets", () => {
  assert.equal(isTabPanelTarget(null), false);
  assert.equal(isTabPanelTarget({}), false);
});
