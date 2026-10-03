import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import { afterEach, mock, test } from "node:test";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, cleanup, renderHook } from "@testing-library/react";
import React from "react";

registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === "@/features/communities/useCommunities") {
      return { shortCircuit: true, url: "buzz-live-members:communities" };
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (url === "buzz-live-members:communities") {
      return {
        shortCircuit: true,
        format: "module",
        source:
          "export const useCommunities = () => ({ activeCommunity: globalThis.__liveMembersCommunity });",
      };
    }
    return nextLoad(url, context);
  },
});

const { relayClient } = await import("@/shared/api/relayClient");
const { relayMembersFromEvent } = await import("@/shared/api/relayMembers");
const { relaySelfQueryKey } = await import("@/features/moderation/hooks");
const { relayMembersQueryKey, useRelayMembersQuery } = await import(
  "./hooks.ts"
);
const { canModerateChannelMessages } = await import(
  "@/features/messages/lib/canManageMessage"
);
const { useLiveRelayMembers } = await import("./useLiveRelayMembers.ts");

const viewer = "a".repeat(64);
const relaySigner = "b".repeat(64);
const clients = [];

afterEach(() => {
  cleanup();
  for (const client of clients.splice(0)) client.clear();
  mock.restoreAll();
  delete globalThis.__liveMembersCommunity;
});

function deferred() {
  let resolve;
  const promise = new Promise((res) => {
    resolve = res;
  });
  return { promise, resolve };
}

function snapshot(id, createdAt, role, pubkey = relaySigner) {
  return {
    id: id.repeat(64),
    pubkey,
    created_at: createdAt,
    kind: 13534,
    tags: role ? [["member", viewer, role]] : [],
    content: "",
    sig: "c".repeat(128),
  };
}

function createClient(role = "member", signer = relaySigner, createdAt = 100) {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false, gcTime: Infinity } },
  });
  clients.push(client);
  client.setQueryData(relaySelfQueryKey, signer);
  client.setQueryData(
    relayMembersQueryKey,
    relayMembersFromEvent(snapshot("0", createdAt, role)),
  );
  return client;
}

function harness({
  enabled = true,
  pubkey = viewer,
  signer = relaySigner,
} = {}) {
  let client = createClient("member", signer);
  globalThis.__liveMembersCommunity = {
    id: "first",
    relayUrl: "wss://first.example",
  };
  const subscriptions = [];
  mock.method(
    relayClient,
    "subscribeLive",
    async (filter, onEvent, _onReady, _timeout, signal) => {
      const subscription = { filter, onEvent, signal, closed: false };
      subscriptions.push(subscription);
      return () => {
        subscription.closed = true;
      };
    },
  );
  const hook = renderHook(
    (props) => {
      useLiveRelayMembers(props);
      const members = useRelayMembersQuery(false).data;
      const role = members?.find((member) => member.pubkey === viewer)?.role;
      return {
        members,
        canModerate: canModerateChannelMessages(viewer, [], role),
      };
    },
    {
      initialProps: { enabled, pubkey },
      wrapper: ({ children }) =>
        React.createElement(QueryClientProvider, { client }, children),
    },
  );
  return {
    hook,
    subscriptions,
    get client() {
      return client;
    },
    switchClient(nextClient) {
      client = nextClient;
      hook.rerender({ enabled, pubkey });
    },
  };
}

async function flush(action = () => {}) {
  await act(async () => {
    action();
    await new Promise((resolve) => setTimeout(resolve, 0));
    await new Promise((resolve) => setTimeout(resolve, 0));
  });
}

test("a live snapshot adds and removes moderation permission for a member", async () => {
  const h = harness();
  await flush();
  assert.equal(h.subscriptions.length, 1);
  const subscription = h.subscriptions[0];
  assert.deepEqual(subscription.filter, {
    kinds: [13534],
    authors: [relaySigner],
    limit: 1,
  });
  assert.equal(h.hook.result.current.canModerate, false);
  await flush(() => subscription.onEvent(snapshot("1", 101, "admin")));
  assert.equal(h.hook.result.current.canModerate, true);
  await flush(() => subscription.onEvent(snapshot("2", 102, "member")));
  assert.equal(h.hook.result.current.canModerate, false);
  await flush(() => subscription.onEvent(snapshot("3", 103, null)));
  assert.deepEqual(h.hook.result.current.members, []);
  assert.equal(subscription.closed, false);
});

test("inactive, missing identity and missing relay signer create no live subscription", async () => {
  for (const options of [
    { enabled: false },
    { pubkey: "" },
    { signer: null },
  ]) {
    const h = harness(options);
    await flush();
    assert.equal(h.subscriptions.length, 0);
    h.hook.unmount();
    mock.restoreAll();
  }
});

test("older snapshots, same-second replays and other authors cannot restore an old role", async () => {
  const h = harness();
  await flush();
  const subscription = h.subscriptions[0];
  await flush(() => subscription.onEvent(snapshot("1", 101, "admin")));
  await flush(() => subscription.onEvent(snapshot("2", 101, "member")));
  await flush(() => {
    subscription.onEvent(snapshot("1", 101, "admin"));
    subscription.onEvent(snapshot("3", 100, "admin"));
    subscription.onEvent(snapshot("4", 102, "admin", viewer));
    subscription.onEvent({ ...snapshot("5", 103, "admin"), kind: 9 });
  });
  assert.equal(h.hook.result.current.canModerate, false);
  assert.equal(
    h.hook.result.current.members[0].createdAt,
    new Date(101_000).toISOString(),
  );
});

test("the first live frame cannot overwrite a newer cached snapshot", async () => {
  const h = harness();
  await flush();
  await flush(() => h.subscriptions[0].onEvent(snapshot("1", 99, "admin")));
  assert.equal(h.hook.result.current.canModerate, false);
  assert.equal(
    h.hook.result.current.members[0].createdAt,
    new Date(100_000).toISOString(),
  );
});

test("an in-flight roster query is cancelled before the live cache update", async () => {
  const h = harness();
  await flush();
  const request = deferred();
  let requestSignal;
  const pending = h.client
    .fetchQuery({
      queryKey: relayMembersQueryKey,
      staleTime: 0,
      queryFn: ({ signal }) => {
        requestSignal = signal;
        return request.promise;
      },
    })
    .catch((error) => error);
  assert.equal(requestSignal.aborted, false);
  await flush(() => h.subscriptions[0].onEvent(snapshot("1", 101, "admin")));
  assert.equal(requestSignal.aborted, true);
  assert.equal(h.hook.result.current.canModerate, true);
  await flush(() =>
    request.resolve(relayMembersFromEvent(snapshot("0", 100, "member"))),
  );
  await pending;
  assert.equal(h.hook.result.current.canModerate, true);
});

test("a newer live frame wins when an older cancellation finishes last", async () => {
  const h = harness();
  await flush();
  const waits = [];
  const cancelQueries = h.client.cancelQueries.bind(h.client);
  mock.method(h.client, "cancelQueries", async (filters) => {
    const wait = deferred();
    waits.push(wait);
    await cancelQueries(filters);
    await wait.promise;
  });
  await flush(() => {
    h.subscriptions[0].onEvent(snapshot("1", 101, "admin"));
    h.subscriptions[0].onEvent(snapshot("2", 102, "member"));
  });
  assert.equal(waits.length, 2);
  await flush(() => waits[1].resolve());
  await flush(() => waits[0].resolve());
  assert.equal(h.hook.result.current.canModerate, false);
  assert.equal(
    h.hook.result.current.members[0].createdAt,
    new Date(102_000).toISOString(),
  );
});

test("community switch rejects old callbacks and releases the old subscription", async () => {
  const h = harness();
  await flush();
  const old = h.subscriptions[0];
  globalThis.__liveMembersCommunity = {
    id: "second",
    relayUrl: "wss://second.example",
  };
  h.hook.rerender({ enabled: true, pubkey: viewer });
  await flush();
  assert.equal(h.subscriptions.length, 2);
  assert.equal(old.closed, true);
  assert.equal(old.signal.aborted, true);
  await flush(() => old.onEvent(snapshot("1", 200, "admin")));
  assert.equal(h.hook.result.current.canModerate, false);
  await flush(() => h.subscriptions[1].onEvent(snapshot("2", 101, "admin")));
  assert.equal(h.hook.result.current.canModerate, true);
});

test("a query client switch retires an update already waiting on cancellation", async () => {
  const h = harness();
  await flush();
  const oldClient = h.client;
  const wait = deferred();
  const cancelQueries = oldClient.cancelQueries.bind(oldClient);
  mock.method(oldClient, "cancelQueries", async (filters) => {
    await cancelQueries(filters);
    await wait.promise;
  });
  await flush(() => h.subscriptions[0].onEvent(snapshot("1", 101, "admin")));
  h.switchClient(createClient());
  await flush(() => wait.resolve());
  assert.equal(oldClient.getQueryData(relayMembersQueryKey)[0].role, "member");
  assert.equal(h.hook.result.current.canModerate, false);
  await flush(() => h.subscriptions[1].onEvent(snapshot("2", 102, "admin")));
  assert.equal(h.client.getQueryData(relayMembersQueryKey)[0].role, "admin");
});

test("unmount rejects a waiting update and a subscription that opens late", async () => {
  const opening = deferred();
  const h = harness();
  await flush();
  const wait = deferred();
  const cancelQueries = h.client.cancelQueries.bind(h.client);
  mock.method(h.client, "cancelQueries", async (filters) => {
    await cancelQueries(filters);
    await wait.promise;
  });
  await flush(() => h.subscriptions[0].onEvent(snapshot("1", 101, "admin")));
  h.hook.unmount();
  await flush(() => wait.resolve());
  assert.equal(h.client.getQueryData(relayMembersQueryKey)[0].role, "member");
  assert.equal(h.subscriptions[0].closed, true);
  assert.equal(h.subscriptions[0].signal.aborted, true);

  let lateClosed = false;
  mock.method(relayClient, "subscribeLive", () => opening.promise);
  const client = createClient();
  const late = renderHook(
    () => useLiveRelayMembers({ enabled: true, pubkey: viewer }),
    {
      wrapper: ({ children }) =>
        React.createElement(QueryClientProvider, { client }, children),
    },
  );
  late.unmount();
  await flush(() =>
    opening.resolve(() => {
      lateClosed = true;
    }),
  );
  assert.equal(lateClosed, true);
});
