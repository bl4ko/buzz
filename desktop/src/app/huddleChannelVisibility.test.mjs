import assert from "node:assert/strict";
import test from "node:test";

import { shouldShowSidebarChannel } from "./huddleChannelVisibility.ts";

test("ordinary and huddle backing channels stay visible until archived", () => {
  for (const channel of [
    { id: "ordinary", name: "general", ttlSeconds: null },
    {
      id: "huddle",
      name: "huddle-cb879efb",
      channelType: "stream",
      visibility: "private",
      ttlSeconds: 3_600,
    },
  ]) {
    assert.equal(
      shouldShowSidebarChannel({ ...channel, archivedAt: null }),
      true,
    );
    assert.equal(
      shouldShowSidebarChannel({ ...channel, archivedAt: 1 }),
      false,
    );
  }
});
