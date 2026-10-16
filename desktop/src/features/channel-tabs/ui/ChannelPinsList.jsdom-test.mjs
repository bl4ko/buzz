import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import * as React from "react";
import { act } from "react";
import { createRoot } from "react-dom/client";

import { ChannelPinsList } from "./ChannelPinsList.tsx";

let root;
let container;

afterEach(async () => {
  await act(async () => root.unmount());
  container.remove();
});

test("clicking a pin row opens its message", async () => {
  const opened = [];
  const item = {
    target: {
      id: "m1",
      pubkey: "a".repeat(64),
      created_at: 10,
      kind: 9,
      tags: [["h", "c"]],
      content: "hello",
      sig: "",
    },
  };
  container = document.createElement("div");
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () =>
    root.render(
      React.createElement(ChannelPinsList, {
        pinnedMessages: [item],
        profiles: undefined,
        canPin: false,
        isLoading: false,
        onOpenMessage: (pin) => opened.push(pin.target.id),
        onUnpin: () => {},
      }),
    ),
  );
  await act(async () =>
    container.querySelector('[data-testid="channel-pin-row"] button').click(),
  );
  assert.deepEqual(opened, ["m1"]);
});
