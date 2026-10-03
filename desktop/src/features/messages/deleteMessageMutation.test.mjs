import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import { afterEach, test } from "node:test";
import { JSDOM } from "jsdom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import React from "react";

registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === "@/shared/api/tauri" || specifier === "sonner") {
      return { shortCircuit: true, url: `buzz-delete-stub:${specifier}` };
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (url === "buzz-delete-stub:@/shared/api/tauri") {
      return {
        shortCircuit: true,
        format: "module",
        source:
          "export const deleteMessage = (...args) => globalThis.__deleteMessage(...args); export const invokeTauri = async () => [];",
      };
    }
    if (url === "buzz-delete-stub:sonner") {
      return {
        shortCircuit: true,
        format: "module",
        source:
          "export const toast = { error: (...args) => globalThis.__deleteError(...args) };",
      };
    }
    return nextLoad(url, context);
  },
});

const dom = new JSDOM("<!doctype html><html><body></body></html>", {
  url: "http://localhost",
});
Object.assign(globalThis, {
  IS_REACT_ACT_ENVIRONMENT: true,
  document: dom.window.document,
  HTMLElement: dom.window.HTMLElement,
  window: dom.window,
});

const { act, cleanup, renderHook } = await import("@testing-library/react");
const { useDeleteMessageMutation } = await import("./deleteMessageMutation.ts");
const { channelMessagesKey, channelWindowKey, threadRepliesKey } = await import(
  "./lib/messageQueryKeys.ts"
);
const {
  emptyChannelWindowStore,
  flattenChannelWindowEvents,
  mergeLiveChannelWindowEvent,
  replaceNewestChannelWindow,
} = await import("./lib/channelWindowStore.ts");
const { projectChannelWindowMessages } = await import(
  "./lib/projectChannelWindow.ts"
);
const { formatTimelineMessages } = await import(
  "./lib/formatTimelineMessages.ts"
);

const clients = [];
afterEach(() => {
  cleanup();
  for (const client of clients.splice(0)) client.clear();
});

function event(id, tags = []) {
  return {
    id: id.repeat(64),
    pubkey: "a".repeat(64),
    kind: 9,
    created_at: 100,
    content: id,
    tags,
    sig: "b".repeat(128),
  };
}

function page(events) {
  return {
    startCursor: null,
    rows: events.map((event) => ({ event, thread: null })),
    aux: [],
    nextCursor: null,
    hasMore: false,
  };
}

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

function harness() {
  const channelId = "36411e44-0e2d-4cfe-bd6e-567eb169db9f";
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  clients.push(client);
  const root = event("1", [["h", channelId]]);
  const reply = event("2", [
    ["h", channelId],
    ["e", root.id, "", "root"],
    ["e", root.id, "", "reply"],
  ]);
  reply.created_at = 101;
  const messagesKey = channelMessagesKey(channelId);
  const windowKey = channelWindowKey(channelId);
  const threadKey = threadRepliesKey(channelId, root.id);
  client.setQueryData(messagesKey, [root, reply]);
  client.setQueryData(
    windowKey,
    replaceNewestChannelWindow(emptyChannelWindowStore(), page([root])),
  );
  client.setQueryData(threadKey, [root, reply]);
  const requests = [];
  const errors = [];
  globalThis.__deleteMessage = (channelId, eventId) => {
    const result = deferred();
    requests.push({ channelId, eventId, result });
    return result.promise;
  };
  globalThis.__deleteError = (error) => errors.push(error);
  const hook = renderHook(({ channel }) => useDeleteMessageMutation(channel), {
    initialProps: { channel: { id: channelId } },
    wrapper: ({ children }) =>
      React.createElement(QueryClientProvider, { client }, children),
  });
  return {
    client,
    channelId,
    messagesKey,
    windowKey,
    threadKey,
    root,
    reply,
    requests,
    errors,
    hook,
  };
}

function visible(events) {
  return formatTimelineMessages(events, null, undefined, null).map(
    (message) => message.id,
  );
}

async function startDelete(h, target) {
  let pending;
  await act(async () => {
    pending = h.hook.result.current.mutateAsync({ eventId: target.id });
    pending.catch(() => {});
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
  });
  assert.ok(h.requests.some((request) => request.eventId === target.id));
  return { pending };
}

function accepted(h, target, id = "d") {
  return {
    ...event(id),
    kind: 5,
    content: "",
    tags: [
      ["h", h.channelId],
      ["e", target.id],
    ],
  };
}

test("deletion hides only its target in the channel window and thread before the relay replies", async () => {
  const h = harness();
  const { pending } = await startDelete(h, h.root);
  assert.deepEqual(visible(h.client.getQueryData(h.messagesKey)), [h.reply.id]);
  assert.deepEqual(visible(h.client.getQueryData(h.threadKey)), [h.reply.id]);
  assert.deepEqual(
    visible(flattenChannelWindowEvents(h.client.getQueryData(h.windowKey))),
    [],
  );
  await act(async () => {
    h.requests[0].result.resolve(accepted(h, h.root));
    await pending;
  });
});

test("failure removes only its pending marker and preserves live additions", async () => {
  const h = harness();
  const { pending } = await startDelete(h, h.root);
  const live = { ...event("3", [["h", h.channelId]]), created_at: 110 };
  act(() => {
    h.client.setQueryData(h.windowKey, (store) =>
      mergeLiveChannelWindowEvent(store, live),
    );
    projectChannelWindowMessages(h.client, h.channelId);
    h.client.setQueryData(h.threadKey, (events) => [...events, live]);
  });
  await act(async () => {
    h.requests[0].result.reject(new Error("relay unavailable"));
    await assert.rejects(pending, /relay unavailable/);
  });
  assert.deepEqual(visible(h.client.getQueryData(h.messagesKey)), [
    h.root.id,
    h.reply.id,
    live.id,
  ]);
  assert.deepEqual(visible(h.client.getQueryData(h.threadKey)), [
    h.root.id,
    h.reply.id,
    live.id,
  ]);
  assert.equal(h.errors.length, 1);
  assert.ok(
    h.client.getQueryData(h.windowKey).liveAux.every((event) => !event.pending),
  );
});

test("a stale window and thread response cannot restore a pending deletion", async () => {
  const h = harness();
  const { pending } = await startDelete(h, h.root);
  const stale = deferred();
  const fetching = h.client.fetchQuery({
    queryKey: h.threadKey,
    queryFn: () => stale.promise,
  });
  act(() => {
    h.client.setQueryData(h.windowKey, (store) =>
      replaceNewestChannelWindow(store, page([h.root])),
    );
    projectChannelWindowMessages(h.client, h.channelId);
  });
  await act(async () => {
    stale.resolve([h.root, h.reply]);
    await fetching;
  });
  assert.deepEqual(visible(h.client.getQueryData(h.messagesKey)), [h.reply.id]);
  assert.deepEqual(visible(h.client.getQueryData(h.threadKey)), [h.reply.id]);
  await act(async () => {
    h.requests[0].result.reject(new Error("no connection"));
    await assert.rejects(pending, /no connection/);
  });
  assert.deepEqual(visible(h.client.getQueryData(h.messagesKey)), [
    h.root.id,
    h.reply.id,
  ]);
  assert.deepEqual(visible(h.client.getQueryData(h.threadKey)), [
    h.root.id,
    h.reply.id,
  ]);
});

test("accepted deletion replaces the pending marker and remains hidden through a head refetch", async () => {
  const h = harness();
  const { pending } = await startDelete(h, h.root);
  const signed = accepted(h, h.root);
  await act(async () => {
    h.requests[0].result.resolve(signed);
    await pending;
  });
  for (const key of [h.messagesKey, h.threadKey]) {
    const events = h.client.getQueryData(key);
    assert.ok(
      events.some(
        (event) => event.id === signed.id && event.sig === signed.sig,
      ),
    );
    assert.ok(
      events.every((event) => !event.pending && event.id !== h.root.id),
    );
  }
  act(() => {
    h.client.setQueryData(h.windowKey, (store) =>
      replaceNewestChannelWindow(store, page([h.root])),
    );
    projectChannelWindowMessages(h.client, h.channelId);
  });
  assert.deepEqual(visible(h.client.getQueryData(h.messagesKey)), [h.reply.id]);
});

test("one failed deletion cannot undo another concurrent accepted deletion", async () => {
  const h = harness();
  const first = await startDelete(h, h.root);
  const second = await startDelete(h, h.reply);
  assert.deepEqual(visible(h.client.getQueryData(h.threadKey)), []);
  await act(async () => {
    h.requests[1].result.resolve(accepted(h, h.reply));
    await second.pending;
    h.requests[0].result.reject(new Error("not permitted"));
    await assert.rejects(first.pending, /not permitted/);
  });
  assert.deepEqual(visible(h.client.getQueryData(h.messagesKey)), [h.root.id]);
  assert.deepEqual(visible(h.client.getQueryData(h.threadKey)), [h.root.id]);
});

test("channel navigation keeps the mutation and its cache updates in the captured channel", async () => {
  const h = harness();
  const { pending } = await startDelete(h, h.root);
  const otherKey = channelMessagesKey("other-channel");
  const other = event("4");
  act(() => {
    h.client.setQueryData(otherKey, [other]);
    h.hook.rerender({ channel: { id: "other-channel" } });
  });
  await act(async () => {
    h.requests[0].result.resolve(accepted(h, h.root));
    await pending;
  });
  assert.equal(h.requests[0].channelId, h.channelId);
  assert.deepEqual(h.client.getQueryData(otherKey), [other]);
  assert.deepEqual(visible(h.client.getQueryData(h.messagesKey)), [h.reply.id]);
});

test("a workspace cache reset prevents a late response from changing the new workspace", async () => {
  const h = harness();
  const { pending } = await startDelete(h, h.root);
  const replacement = event("5");
  act(() => {
    h.client.clear();
    h.client.setQueryData(h.messagesKey, [replacement]);
  });
  await act(async () => {
    h.requests[0].result.resolve(accepted(h, h.root));
    await pending;
  });
  assert.deepEqual(h.client.getQueryData(h.messagesKey), [replacement]);
  assert.equal(h.client.getQueryData(h.windowKey), undefined);
});
