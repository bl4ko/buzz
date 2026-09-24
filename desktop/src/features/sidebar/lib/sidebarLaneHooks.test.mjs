import assert from "node:assert/strict";
import { after, before, beforeEach, mock, test } from "node:test";

import { JSDOM } from "jsdom";

const dom = new JSDOM("<!doctype html>", { url: "http://localhost" });
before(() => {
  Object.assign(globalThis, {
    document: dom.window.document,
    window: dom.window,
    IS_REACT_ACT_ENVIRONMENT: true,
  });
});
after(() => dom.window.close());

const PK = "f".repeat(64);
const RELAY = "wss://r.test";
let fx;
let seq = 0;
const ev = (dTag, json, createdAt) => ({
  id: String(++seq).padStart(64, "0"),
  pubkey: PK,
  kind: 30078,
  created_at: createdAt,
  content: JSON.stringify(json),
  tags: [["d", dTag]],
  sig: "s",
});

async function harness() {
  const rtl = await import("@testing-library/react");
  const { relayClient } = await import("@/shared/api/relayClient");
  mock.method(relayClient, "fetchEvents", async (filter) => {
    const head = fx.heads[filter["#d"][0]];
    if (fx.gate) await fx.gate;
    return head ? [head] : [];
  });
  mock.method(relayClient, "subscribeLive", async () => async () => {});
  mock.method(relayClient, "subscribeToReconnects", (fn) => {
    fx.reconnect = fn;
    return () => {};
  });
  mock.method(relayClient, "publishEvent", async (event, _t, _e, isCurrent) => {
    if (fx.holdPublish) await fx.holdPublish;
    if (isCurrent && !isCurrent()) throw new Error("canceled");
    fx.published.push(event);
    fx.heads[event.tags[0][1]] = event;
  });
  mock.method(console, "warn", () => {});
  window.__TAURI_INTERNALS__ = {
    invoke: async (cmd, args) => {
      if (cmd === "nip44_encrypt_to_self") return args.plaintext;
      if (cmd === "nip44_decrypt_from_self") return args.ciphertext;
      if (cmd === "sign_event")
        return JSON.stringify({
          ...ev(args.tags[0][1], JSON.parse(args.content), args.createdAt),
          content: args.content,
        });
      throw new Error(`unmocked ${cmd}`);
    },
  };
  // Advance fake time in steps, letting async work between timers settle.
  const advance = async (ms) => {
    for (let t = 0; t < ms; t += 1_000) {
      await rtl.act(async () => {
        mock.timers.tick(1_000);
        for (let i = 0; i < 10; i++) await new Promise(setImmediate);
      });
    }
  };
  return { ...rtl, advance };
}

beforeEach(() => {
  window.localStorage.clear();
  mock.restoreAll();
  mock.timers.reset();
  mock.timers.enable({ apis: ["setTimeout", "Date"], now: 1e12 });
  fx = { heads: {}, published: [], reconnect: null };
});

for (const [name, modPath, hookName, dTag, idsKey] of [
  [
    "stars",
    "./useChannelStars.ts",
    "useChannelStars",
    "channel-stars",
    "starredChannelIds",
  ],
  [
    "mutes",
    "./useChannelMutes.ts",
    "useChannelMutes",
    "channel-mutes",
    "mutedChannelIds",
  ],
]) {
  test(`${name}: the real hook recovers a missed head on the 5 s and steady 60 s ticks`, async () => {
    const { renderHook, advance, cleanup } = await harness();
    const hook = (await import(modPath))[hookName];
    const entry = (ids) =>
      Object.fromEntries(
        ids.map((id) => [
          id,
          { [name === "stars" ? "starred" : "muted"]: true, updatedAt: 1 },
        ]),
      );
    const { result } = renderHook(() => hook(PK, RELAY));
    await advance(1_000);
    assert.equal(result.current[idsKey].size, 0);
    fx.heads[dTag] = ev(dTag, { version: 1, channels: entry(["c1"]) }, 100);
    await advance(5_000);
    assert.deepEqual([...result.current[idsKey]], ["c1"]);
    await advance(10_000 + 30_000); // back-off climbs to its steady 60 s
    fx.heads[dTag] = ev(
      dTag,
      { version: 1, channels: entry(["c1", "c2"]) },
      200,
    );
    await advance(60_000);
    assert.deepEqual([...result.current[idsKey]].sort(), ["c1", "c2"]);
    cleanup();
  });
}

test("sections hook: 60 s tick, reconnect, cross-tab, pending edit and in-flight unmount", async () => {
  const { renderHook, act, advance, cleanup } = await harness();
  const { useChannelSections } = await import("./useChannelSections.ts");
  const { storageKey } = await import("./channelSectionsStorage.ts");
  const legacy = (names) => ({
    version: 1,
    sections: names.map((n, order) => ({ id: n, name: n, order })),
    assignments: {},
  });
  fx.heads["channel-sections"] = ev("channel-sections", legacy(["a"]), 100);
  const { result, unmount } = renderHook(() => useChannelSections(PK, RELAY));
  await advance(1_000);
  const names = () => result.current.sections.map((s) => s.name);
  assert.deepEqual(names(), ["a"]);

  // Missed live event: the steady cadence (5+10+30+60) picks it up.
  fx.heads["channel-sections"] = ev(
    "channel-sections",
    legacy(["a", "b"]),
    200,
  );
  await advance(105_000);
  assert.deepEqual(names(), ["a", "b"]);

  // Reconnect re-reads.
  fx.heads["channel-sections"] = ev(
    "channel-sections",
    legacy(["a", "b", "c"]),
    300,
  );
  await act(async () => fx.reconnect());
  await advance(1_000);
  assert.deepEqual(names(), ["a", "b", "c"]);

  // Another tab's write merges (never replaces).
  const other = legacy(["d"]);
  await act(async () =>
    window.dispatchEvent(
      new window.StorageEvent("storage", {
        key: storageKey(PK, RELAY),
        newValue: JSON.stringify(other),
      }),
    ),
  );
  assert.deepEqual(names().sort(), ["a", "b", "c", "d"]);

  // A read (here, reconnect) during the edit debounce merges but cannot
  // publish early or shorten the debounce.
  const before = fx.published.length;
  act(() => void result.current.createSection("e"));
  fx.heads["channel-sections"] = ev(
    "channel-sections",
    legacy(["a", "b", "c", "f"]),
    400,
  );
  await act(async () => fx.reconnect());
  await advance(1_000);
  assert.equal(fx.published.length, before, "held by the debounce");
  assert.ok(names().includes("f") && names().includes("e"));

  // Unmount while the publish is in flight: nothing reaches the socket.
  let release;
  fx.holdPublish = new Promise((r) => (release = r));
  await advance(2_000);
  unmount();
  release();
  await advance(1_000);
  assert.equal(fx.published.length, before);
  cleanup();
});

test("sections hook: create appends past gaps; reorder completes against the live list", async () => {
  const { renderHook, act, advance, cleanup } = await harness();
  const { useChannelSections } = await import("./useChannelSections.ts");
  const { storageKey } = await import("./channelSectionsStorage.ts");
  const { result } = renderHook(() => useChannelSections(PK, RELAY));
  await advance(1_000);
  const names = () => result.current.sections.map((s) => s.name);
  const ids = {};
  for (const n of ["a", "b", "c"])
    act(() => {
      ids[n] = result.current.createSection(n).id;
    });
  act(() => result.current.deleteSection(ids.b)); // canonical ranks 0 and 2
  act(() => void result.current.createSection("d"));
  assert.deepEqual(names(), ["a", "c", "d"], "new section sorts last");

  // A section merged in from another tab after the drag snapshot was taken.
  const snapshot = result.current.sections.map((s) => s.id);
  await act(async () =>
    window.dispatchEvent(
      new window.StorageEvent("storage", {
        key: storageKey(PK, RELAY),
        newValue: JSON.stringify({
          version: 1,
          sections: [{ id: "x", name: "x", order: 9 }],
          assignments: {},
        }),
      }),
    ),
  );
  act(() =>
    result.current.reorderSections([...snapshot].reverse().concat("gone")),
  );
  assert.deepEqual(names(), ["d", "c", "a", "x"]);
  const orders = JSON.parse(window.localStorage.getItem(storageKey(PK, RELAY)))
    .meta.s;
  assert.ok(orders.x.order, "the missing live section got an order register");
  cleanup();
});
