import assert from "node:assert/strict";
import { after, afterEach, before, test } from "node:test";
import { QueryClient, QueryObserver } from "@tanstack/react-query";
import { JSDOM } from "jsdom";
import {
  channelMessagesQueryOptions,
  prefetchChannelMessages,
} from "./channelMessagesQuery.ts";
import { channelMessagesKey, channelWindowKey } from "./messageQueryKeys.ts";
import { resolveTimelineQueryLoadingState } from "./timelineLoadingState.ts";

const dom = new JSDOM("", { url: "http://localhost" });
const clients = [];
const channel = { id: "a", channelType: "stream", isMember: true };

before(() => {
  globalThis.window = dom.window;
});
afterEach(() => {
  for (const client of clients.splice(0)) client.clear();
});
after(() => dom.window.close());

function makeClient() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  clients.push(client);
  return client;
}

function page(channelId) {
  return [
    {
      id: `root-${channelId}`,
      pubkey: "b".repeat(64),
      kind: 9,
      created_at: 10,
      content: `message in ${channelId}`,
      tags: [["h", channelId]],
      sig: "",
    },
    {
      id: `bounds-${channelId}`,
      pubkey: "b".repeat(64),
      kind: 39006,
      created_at: 11,
      content: JSON.stringify({ has_more: false, next_cursor: null }),
      tags: [
        ["h", channelId],
        ["d", `${channelId}:head`],
      ],
      sig: "",
    },
  ];
}

function holdRequests() {
  const requests = [];
  window.__TAURI_INTERNALS__ = {
    invoke: (command, args) => {
      assert.equal(command, "get_channel_window");
      return new Promise((resolve, reject) => {
        requests.push({ channelId: args.channelId, resolve, reject });
      });
    },
  };
  return requests;
}

async function tick() {
  await new Promise((resolve) => setImmediate(resolve));
}

test("intent prefetch and channel mount share one request and window", async () => {
  const requests = holdRequests();
  const client = makeClient();
  const prefetch = prefetchChannelMessages(client, channel);
  await tick();
  const observer = new QueryObserver(
    client,
    channelMessagesQueryOptions(client, channel.id),
  );
  const unsubscribe = observer.subscribe(() => {});
  try {
    assert.equal(requests.length, 1);
    requests[0].resolve(page(channel.id));
    await prefetch;
    assert.deepEqual(observer.getCurrentResult().data, [page(channel.id)[0]]);
    assert.equal(
      client.getQueryData(channelWindowKey(channel.id)).pages.length,
      1,
    );
    await prefetchChannelMessages(client, channel);
    assert.equal(requests.length, 1);
  } finally {
    unsubscribe();
  }
});

test("prefetch is limited to two requests and skips forums and nonmembers", async () => {
  const requests = holdRequests();
  const client = makeClient();
  const a = prefetchChannelMessages(client, channel);
  const b = prefetchChannelMessages(client, {
    ...channel,
    id: "b",
    channelType: "dm",
  });
  await prefetchChannelMessages(client, { ...channel, id: "c" });
  await prefetchChannelMessages(client, {
    ...channel,
    id: "forum",
    channelType: "forum",
  });
  await prefetchChannelMessages(client, {
    ...channel,
    id: "private",
    isMember: false,
  });
  await tick();
  assert.deepEqual(
    requests.map((request) => request.channelId),
    ["a", "b"],
  );
  for (const request of requests) request.resolve(page(request.channelId));
  await Promise.all([a, b]);
  const c = prefetchChannelMessages(client, { ...channel, id: "c" });
  await tick();
  assert.equal(requests.length, 3);
  requests[2].resolve(page("c"));
  await c;
  assert.equal(
    client.getQueryData(channelMessagesKey("a"))[0].content,
    "message in a",
  );
  assert.equal(
    client.getQueryData(channelMessagesKey("c"))[0].content,
    "message in c",
  );
});

test("failed prefetch remains an error and can retry on selection", async () => {
  const requests = holdRequests();
  const client = makeClient();
  const prefetch = prefetchChannelMessages(client, channel);
  await tick();
  requests[0].reject(new Error("relay unavailable"));
  await prefetch;
  assert.equal(client.getQueryState(channelMessagesKey("a")).status, "error");
  assert.equal(client.getQueryData(channelWindowKey("a")), undefined);
  const retry = client.fetchQuery(channelMessagesQueryOptions(client, "a"));
  await tick();
  requests[1].resolve(page("a"));
  assert.deepEqual(await retry, [page("a")[0]]);
});

test("canceled prefetch cannot overwrite a replacement window", async () => {
  const requests = holdRequests();
  const client = makeClient();
  const prefetch = prefetchChannelMessages(client, channel);
  await tick();
  await client.cancelQueries({
    queryKey: channelMessagesKey("a"),
    exact: true,
  });
  const replacement = { pages: ["new window"] };
  client.setQueryData(channelWindowKey("a"), replacement);
  requests[0].resolve(page("a"));
  await prefetch;
  await tick();
  assert.equal(client.getQueryData(channelWindowKey("a")), replacement);
});

test("cached channel rows stay visible during a slow background refresh", async () => {
  const requests = holdRequests();
  const client = makeClient();
  const prefetch = prefetchChannelMessages(client, channel);
  await tick();
  requests[0].resolve(page("a"));
  await prefetch;
  const observer = new QueryObserver(
    client,
    channelMessagesQueryOptions(client, "a"),
  );
  const unsubscribe = observer.subscribe(() => {});
  try {
    const refresh = observer.refetch();
    const result = observer.getCurrentResult();
    assert.equal(result.isFetching, true);
    assert.deepEqual(
      resolveTimelineQueryLoadingState("other", "a", {
        isEnabled: true,
        isPending: result.isPending,
        isFetching: result.isFetching,
        isPlaceholderData: result.isPlaceholderData,
        dataLength: result.data?.length ?? null,
        isError: result.isError,
        hasResolvedWindow:
          client.getQueryData(channelWindowKey("a")).pages.length > 0,
      }),
      { settledChannelId: "a", isLoading: false },
    );
    await tick();
    requests[1].resolve(page("a"));
    await refresh;
  } finally {
    unsubscribe();
  }
});
