import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import * as React from "react";
import { act } from "react";
import { createRoot } from "react-dom/client";
import {
  createMemoryHistory,
  createRootRoute,
  createRoute,
  createRouter,
  RouterProvider,
} from "@tanstack/react-router";
import {
  CommunitiesProvider,
  useCommunities,
} from "@/features/communities/useCommunities";
import {
  resetDetachedToastScope,
  setDetachedToastScope,
} from "@/features/messages/lib/detachedToastScope";
import { useReminderNavigation } from "./useReminderNavigation.ts";

const pubkey = "a".repeat(64);
const target = {
  channelId: "channel-1",
  eventId: "message-1",
  authorPubkey: pubkey,
  preview: "saved",
};
let finishRead;
let openMessage;
let communities;
let root;
let container;
let currentPubkey;
let setPubkey;
globalThis.localStorage = window.localStorage;
const tauriMock = {
  invoke(command) {
    assert.equal(command, "get_event");
    return new Promise((resolve) => {
      finishRead = () => resolve(JSON.stringify({ tags: [] }));
    });
  },
};
globalThis.__TAURI_INTERNALS__ = tauriMock;
window.__TAURI_INTERNALS__ = tauriMock;

function Probe() {
  communities = useCommunities();
  const [pubkey, updatePubkey] = React.useState(currentPubkey);
  setPubkey = updatePubkey;
  openMessage = useReminderNavigation(pubkey);
  return null;
}

async function mount() {
  localStorage.clear();
  localStorage.setItem(
    "buzz-communities",
    JSON.stringify([
      { id: "a", relayUrl: "wss://a.example" },
      { id: "b", relayUrl: "wss://b.example" },
    ]),
  );
  localStorage.setItem("buzz-active-community-id", "a");
  currentPubkey = pubkey;
  setDetachedToastScope({ relayUrl: "wss://a.example", signerPubkey: pubkey });
  const route = createRootRoute({ component: Probe });
  const channel = createRoute({
    getParentRoute: () => route,
    path: "/channels/$channelId",
    validateSearch: (search) => search,
  });
  const index = createRoute({ getParentRoute: () => route, path: "/" });
  const router = createRouter({
    routeTree: route.addChildren([index, channel]),
    history: createMemoryHistory({ initialEntries: ["/"] }),
  });
  container = document.createElement("div");
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () => {
    await router.load();
    root.render(
      React.createElement(
        CommunitiesProvider,
        null,
        React.createElement(RouterProvider, { router }),
      ),
    );
  });
  return router;
}

afterEach(() => {
  act(() => root?.unmount());
  root = null;
  container?.remove();
  resetDetachedToastScope();
});

test("opens the saved source message in the current scope", async () => {
  const router = await mount();
  const pending = openMessage(target);
  await act(async () => {
    finishRead();
    await pending;
    await router.load();
  });
  assert.equal(router.state.location.pathname, "/channels/channel-1");
  assert.equal(router.state.location.search.messageId, target.eventId);
});

for (const change of ["community", "round-trip", "identity", "unmount"]) {
  test(`ignores a delayed source lookup after ${change}`, async () => {
    const router = await mount();
    const pending = openMessage(target);
    await act(async () => {
      if (change === "community" || change === "round-trip") {
        communities.switchCommunity("b");
      } else if (change === "identity") {
        setPubkey("b".repeat(64));
      } else {
        root.unmount();
        root = null;
      }
    });
    if (change === "round-trip") {
      await act(async () => communities.switchCommunity("a"));
    }
    await act(async () => {
      finishRead();
      await pending;
    });
    assert.equal(router.state.location.pathname, "/");
  });
}
