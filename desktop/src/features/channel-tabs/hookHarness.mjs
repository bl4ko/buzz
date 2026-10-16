import assert from "node:assert/strict";
import * as React from "react";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";

export function createHookHarness(useValue) {
  const harness = { latest: undefined, root: null, container: null };
  function Probe({ arg }) {
    harness.latest = useValue(arg);
    return null;
  }
  harness.mount = async (arg) => {
    harness.container = document.createElement("div");
    document.body.appendChild(harness.container);
    harness.root = createRoot(harness.container);
    const client = new QueryClient({
      defaultOptions: { queries: { retry: false } },
    });
    await act(async () => {
      harness.root.render(
        React.createElement(
          QueryClientProvider,
          { client },
          React.createElement(Probe, { arg }),
        ),
      );
    });
  };
  harness.waitFor = async (predicate) => {
    for (let attempt = 0; attempt < 50; attempt += 1) {
      if (predicate()) return;
      await act(async () => {
        await new Promise((resolve) => setTimeout(resolve, 5));
      });
    }
    assert.fail("condition was not reached");
  };
  harness.unmount = async () => {
    if (harness.root) await act(async () => harness.root.unmount());
    harness.container?.remove();
    harness.root = null;
    harness.latest = undefined;
  };
  return harness;
}

export function createEventTransport(events, extra = {}) {
  const transport = {
    events,
    live: null,
    liveFilter: null,
    reconnect: null,
    fetched: [],
    signed: [],
    published: [],
    nowSeconds: 5,
    async fetchEvents(filter) {
      transport.fetched.push(filter);
      return transport.events;
    },
    async subscribeLive(filter, onEvent) {
      transport.liveFilter = filter;
      transport.live = onEvent;
      return () => {
        transport.live = null;
      };
    },
    subscribeToReconnects(listener) {
      transport.reconnect = listener;
      return () => {};
    },
    async signEvent(input) {
      transport.signed.push(input);
      return {
        id: `s${transport.signed.length}`,
        pubkey: "f".repeat(64),
        created_at: input.createdAt,
        kind: input.kind,
        tags: input.tags,
        content: input.content,
        sig: "",
      };
    },
    async publishEvent(event) {
      transport.published.push(event);
      return event;
    },
    now() {
      return transport.nowSeconds;
    },
    ...extra,
  };
  return transport;
}
