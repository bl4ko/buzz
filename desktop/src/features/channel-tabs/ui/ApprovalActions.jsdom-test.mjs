import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import * as React from "react";
import { act } from "react";
import { createRoot } from "react-dom/client";

import { ApprovalActions } from "./ApprovalActions.tsx";

let root;
let container;

async function render(props) {
  container = document.createElement("div");
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () =>
    root.render(React.createElement(ApprovalActions, props)),
  );
}

afterEach(async () => {
  await act(async () => root.unmount());
  container.remove();
});

test("approve and deny send the agreed emoji", async () => {
  const picked = [];
  await render({
    reactions: [],
    disabled: false,
    onSelect: (emoji) => picked.push(emoji),
  });
  const [approve, deny] = container.querySelectorAll(
    '[data-testid="approval-actions"] button',
  );
  await act(async () => approve.click());
  await act(async () => deny.click());
  assert.deepEqual(picked, ["✅", "❌"]);
});

test("a decided approval shows the decision and no buttons", async () => {
  await render({
    reactions: [
      { emoji: "✅", count: 1, reactedByCurrentUser: true, users: [] },
    ],
    disabled: false,
    onSelect: () => {},
  });
  assert.equal(
    container.querySelector('[data-testid="approval-actions"]'),
    null,
  );
  assert.equal(
    container.querySelector('[data-testid="approval-decision"]').textContent,
    "You approved",
  );
});
