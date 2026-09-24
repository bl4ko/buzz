import assert from "node:assert/strict";
import test, { beforeEach, mock } from "node:test";

import { relayClient } from "@/shared/api/relayClient";
import { SECTIONS_LANE, projectSections } from "./channelSectionsSync.ts";
import { SORT_LANE, projectSort } from "./channelSortSync.ts";
import { LaneReconciler } from "./sidebarLaneReconciler.ts";
import { LaneStore } from "./sidebarLaneStore.ts";
import { canonical, setRegs } from "./sidebarLwwMap.ts";

const PK = "f".repeat(64);
const RELAY = "wss://r.test";
const storage = new Map();
globalThis.window ??= {};
Object.assign(globalThis.window, {
  localStorage: {
    getItem: (k) => storage.get(k) ?? null,
    setItem: (k, v) => {
      if (fx.storageFails) throw new Error("quota");
      storage.set(k, v);
    },
    removeItem: (k) => storage.delete(k),
  },
  addEventListener: () => {},
  removeEventListener: () => {},
});

/** Fake relay (one replaceable head), identity crypto, scripted failures. */
let fx;
let seq = 0;
beforeEach(() => {
  storage.clear();
  mock.restoreAll();
  fx = {
    head: null,
    published: [],
    fetchFails: false,
    publish: "ok",
    storageFails: false,
    badDecrypt: new Set(),
  };
  globalThis.window.__TAURI_INTERNALS__ = {
    invoke: async (cmd, args) => {
      if (cmd === "nip44_encrypt_to_self") return args.plaintext;
      if (cmd === "nip44_decrypt_from_self") {
        if (fx.badDecrypt.has(args.ciphertext)) throw new Error("bad");
        return args.ciphertext;
      }
      if (cmd === "sign_event")
        return JSON.stringify(ev(args.content, args.createdAt));
      throw new Error(`unmocked ${cmd}`);
    },
  };
  mock.method(relayClient, "fetchEvents", async () => {
    if (fx.fetchFails) throw new Error("offline");
    return fx.head ? [fx.head] : [];
  });
  mock.method(console, "warn", () => {});
  mock.method(relayClient, "publishEvent", async (event) => {
    fx.published.push(event);
    if (fx.publish === "timeout") throw new Error("Timed out");
    if (fx.publish === "reject") throw new Error("blocked: nope");
    if (fx.publish === "duplicate") throw new Error("duplicate: have it");
    fx.head = event;
  });
});

function ev(content, createdAt) {
  seq++;
  return {
    id: String(seq).padStart(64, "0"),
    pubkey: PK,
    kind: 30078,
    created_at: createdAt,
    content,
    tags: [],
    sig: "s",
  };
}

function device(lane) {
  const store = new LaneStore(lane, PK, RELAY);
  const rec = new LaneReconciler(lane, store, PK, RELAY);
  rec.schedule = () => {}; // timers are driven explicitly via read()
  return { store, rec };
}

const settle = () => new Promise((r) => setTimeout(r, 0));
async function sync(d) {
  await d.rec.read();
  for (let i = 0; i < 5; i++) await settle();
}

const LANES = [
  {
    name: "sections",
    lane: SECTIONS_LANE,
    edit: (tree, key, value) =>
      setRegs(tree, [
        [["s", key, "name"], value],
        [["s", key, "order"], 0],
        [["s", key, "live"], true],
      ]),
    remove: (tree, key) => setRegs(tree, [[["s", key, "live"], false]]),
    view: (tree) =>
      Object.fromEntries(
        projectSections(tree).sections.map((s) => [s.id, s.name]),
      ),
    legacy: (items) => ({
      version: 1,
      sections: Object.entries(items).map(([id, name], order) => ({
        id,
        name,
        order,
      })),
      assignments: {},
    }),
    big: (tree) =>
      setRegs(
        tree,
        Array.from({ length: 101 }, (_, i) => [
          ["s", `s${i}`, "live"],
          true,
        ]).flatMap((w, i) => [
          w,
          [["s", `s${i}`, "name"], "n"],
          [["s", `s${i}`, "order"], i],
        ]),
      ),
  },
  {
    name: "sort",
    lane: SORT_LANE,
    edit: (tree, key, value) =>
      setRegs(tree, [
        [
          ["g", `section:${key}`],
          value === "B" || value === "Y" ? "recent" : "alpha",
        ],
      ]),
    remove: (tree, key) => setRegs(tree, [[["g", `section:${key}`], null]]),
    view: (tree) =>
      Object.fromEntries(
        Object.entries(projectSort(tree).groups).map(([k, m]) => [
          k.slice(8),
          m === "recent" ? "B" : "A",
        ]),
      ),
    legacy: (items) => ({
      version: 1,
      groups: Object.fromEntries(
        Object.entries(items).map(([k, v]) => [
          `section:${k}`,
          v === "B" ? "recent" : "alpha",
        ]),
      ),
    }),
    big: (tree) =>
      setRegs(
        tree,
        Array.from({ length: 105 }, (_, i) => [
          ["g", `section:${i}`],
          "recent",
        ]),
      ),
  },
];

for (const L of LANES) {
  test(`${L.name}: new scope with local data publishes its first copy`, async () => {
    const d = device(L.lane);
    d.store.transact((t) => L.edit(t, "k1", "A"));
    await sync(d);
    assert.equal(fx.published.length, 1);
    const doc = JSON.parse(fx.published[0].content);
    assert.equal(doc.version, 1);
    assert.equal(doc.meta.v, 1);
    await sync(d);
    assert.equal(fx.published.length, 1, "equal digest: no republish");
  });

  test(`${L.name}: absence after a seen head holds (never publishes over it)`, async () => {
    const d = device(L.lane);
    d.store.transact((t) => L.edit(t, "k1", "A"));
    await sync(d);
    fx.head = null; // relay transiently returns nothing
    const d2 = device(L.lane); // restart: watermark > 0
    d2.store.transact((t) => L.edit(t, "k2", "B"));
    await sync(d2);
    assert.equal(fx.published.length, 1);
    assert.equal(d2.rec.head.status, "unknown");
  });

  test(`${L.name}: stale device merges instead of overwriting newer items`, async () => {
    const a = device(L.lane);
    a.store.transact((t) => L.edit(t, "k1", "A"));
    await sync(a);
    storage.clear(); // B: separate install with its own local cache
    const b = device(L.lane);
    b.store.transact((t) => L.edit(t, "k2", "B"));
    await sync(b);
    assert.deepEqual(L.view(JSON.parse(fx.head.content).meta), {
      k1: "A",
      k2: "B",
    });
    await sync(a);
    assert.deepEqual(L.view(a.store.get()), { k1: "A", k2: "B" });
  });

  test(`${L.name}: a delete on one device survives a stale device's publish`, async () => {
    const a = device(L.lane);
    a.store.transact((t) => L.edit(L.edit(t, "k1", "A"), "k2", "B"));
    await sync(a);
    const snapshot = new Map(storage);
    a.store.transact((t) => L.remove(t, "k1"));
    await sync(a);
    storage.clear();
    for (const [k, v] of snapshot) if (!k.includes("clock")) storage.set(k, v);
    const stale = device(L.lane); // cache from before the delete
    stale.store.transact((t) => L.edit(t, "k3", "A"));
    await sync(stale);
    assert.deepEqual(L.view(JSON.parse(fx.head.content).meta), {
      k2: "B",
      k3: "A",
    });
  });

  test(`${L.name}: missed live event recovered by the cadence read`, async () => {
    const a = device(L.lane);
    const b = device(L.lane);
    await sync(b);
    a.store.transact((t) => L.edit(t, "k1", "Y"));
    await sync(a); // b never receives the live event
    await sync(b); // 60 s recovery read
    assert.deepEqual(L.view(b.store.get()), L.view(a.store.get()));
  });

  test(`${L.name}: old writer without meta adds items but cannot delete`, async () => {
    const a = device(L.lane);
    a.store.transact((t) => L.edit(t, "k1", "A"));
    await sync(a);
    fx.head = ev(JSON.stringify(L.legacy({ k9: "B" })), fx.head.created_at + 1);
    await sync(a);
    assert.deepEqual(L.view(a.store.get()), { k1: "A", k9: "B" });
    assert.equal(
      JSON.parse(fx.head.content).meta.v,
      1,
      "next upgraded publish restores meta",
    );
  });

  test(`${L.name}: meta-less local cache imports once at a stable stamp`, async () => {
    storage.set(
      L.lane.storageKey(PK, RELAY),
      JSON.stringify(L.legacy({ k1: "A" })),
    );
    const d = device(L.lane);
    const first = canonical(d.store.get());
    assert.deepEqual(L.view(d.store.get()), { k1: "A" });
    assert.equal(canonical(device(L.lane).store.get()), first);
  });

  test(`${L.name}: publish exits (timeout, reject, duplicate) release the attempt`, async () => {
    for (const outcome of ["timeout", "reject", "duplicate"]) {
      storage.clear();
      fx.head = null;
      fx.publish = outcome;
      const d = device(L.lane);
      d.store.transact((t) => L.edit(t, "k1", "A"));
      const before = fx.published.length;
      await sync(d);
      assert.equal(fx.published.length, before + 1, outcome);
      fx.publish = "ok";
      if (outcome === "duplicate") fx.head = fx.published.at(-1);
      await sync(d);
      assert.equal(
        fx.published.length,
        before + (outcome === "duplicate" ? 1 : 2),
        `${outcome} retry`,
      );
    }
  });

  test(`${L.name}: preflight failure publishes nothing and recovers`, async () => {
    const d = device(L.lane);
    d.store.transact((t) => L.edit(t, "k1", "A"));
    fx.fetchFails = true;
    await assert.rejects(d.rec.read());
    assert.equal(fx.published.length, 0);
    fx.fetchFails = false;
    await sync(d);
    assert.equal(fx.published.length, 1);
  });

  test(`${L.name}: unreadable head holds quietly; content never published over it`, async () => {
    const d = device(L.lane);
    d.store.transact((t) => L.edit(t, "k1", "A"));
    fx.head = ev("not json", 10);
    await sync(d);
    assert.equal(d.rec.head.status, "unreadable");
    assert.equal(fx.published.length, 0);
  });

  test(`${L.name}: stale decode merges content but does not settle status`, async () => {
    const d = device(L.lane);
    const older = ev(JSON.stringify(L.legacy({ k1: "A" })), 10);
    const newer = ev("garbage", 11);
    fx.badDecrypt.add("garbage");
    const p = d.rec.ingest(older);
    await d.rec.ingest(newer); // newer head observed before older decode lands
    await p;
    assert.equal(d.rec.head.id, newer.id);
    assert.equal(d.rec.head.status, "unreadable");
    assert.deepEqual(L.view(d.store.get()), { k1: "A" });
  });

  test(`${L.name}: over limit stays local and is not published`, async () => {
    const d = device(L.lane);
    d.store.transact(L.big);
    await sync(d);
    assert.equal(fx.published.length, 0);
    assert.ok(
      storage.get(L.lane.storageKey(PK, RELAY)).length > 1000,
      "kept durable locally",
    );
  });

  test(`${L.name}: failed persistence stays dirty and retries`, async () => {
    const d = device(L.lane);
    fx.storageFails = true;
    d.store.transact((t) => L.edit(t, "k1", "A"));
    assert.equal(storage.size, 0);
    fx.storageFails = false;
    d.store.persist();
    assert.ok(storage.has(L.lane.storageKey(PK, RELAY)));
  });

  test(`${L.name}: identical transaction has no side effects`, () => {
    const d = device(L.lane);
    d.store.transact((t) => L.edit(t, "k1", "A"));
    let notified = 0;
    d.store.subscribe(() => notified++);
    d.store.transact((t) => L.edit(t, "k1", "A"));
    assert.equal(notified, 0);
  });

  test(`${L.name}: destroyed reconciler never publishes`, async () => {
    const d = device(L.lane);
    d.store.transact((t) => L.edit(t, "k1", "A"));
    d.rec.destroy();
    await sync(d);
    assert.equal(fx.published.length, 0);
  });
}

test("sections: projection is live-only, dense integer order, live assignments", () => {
  const A = "a".repeat(16);
  const tree = {
    s: {
      x: { name: [1, A, "X"], order: [1, A, 7], live: [1, A, true] },
      y: { name: [1, A, "Y"], order: [1, A, 3], live: [1, A, true] },
      z: { name: [1, A, "Z"], order: [1, A, 0], live: [1, A, false] },
    },
    a: { c1: [1, A, "x"], c2: [1, A, "z"], c3: [1, A, null] },
  };
  assert.deepEqual(projectSections(tree), {
    sections: [
      { id: "y", name: "Y", order: 0 },
      { id: "x", name: "X", order: 1 },
    ],
    assignments: { c1: "x" },
  });
});

test("sections: rename concurrent with delete stays deleted", async () => {
  const d = device(SECTIONS_LANE);
  d.store.transact((t) => LANES[0].edit(t, "k1", "A"));
  const base = d.store.get();
  const renamed = setRegs(base, [[["s", "k1", "name"], "B"]]);
  const deleted = setRegs(base, [[["s", "k1", "live"], false]]);
  d.store.merge(renamed);
  d.store.merge(deleted);
  assert.deepEqual(projectSections(d.store.get()).sections, []);
});

// ─── stars/mutes: stale-reader recovery through the shared cadence ─────────

test("stars/mutes: recovery applies a found read, skips while pending or after an edit", async () => {
  const { JSDOM } = await import("jsdom");
  const dom = new JSDOM("<!doctype html>", {
    url: "http://localhost",
    pretendToBeVisual: true,
  });
  Object.assign(globalThis, {
    document: dom.window.document,
    IS_REACT_ACT_ENVIRONMENT: true,
  });
  const { renderHook, act, cleanup } = await import("@testing-library/react");
  const { useStaleReaderRecovery } = await import(
    "./useStaleReaderRecovery.ts"
  );
  const React = await import("react");
  let pending = false;
  let revision = 0;
  let fetches = 0;
  const found = (n) => ({
    status: "found",
    data: n,
    createdAt: n,
    eventId: "e",
  });
  const { result } = renderHook(() => {
    const [store, setStore] = React.useState(0);
    useStaleReaderRecovery({
      enabled: true,
      fetch: React.useCallback(async () => {
        fetches++;
        const r = found(fetches);
        if (fetches === 2) revision++; // local edit lands mid-flight
        return r;
      }, []),
      hasPending: React.useCallback(() => pending, []),
      getRevision: React.useCallback(() => revision, []),
      makeUpdater: React.useCallback((n) => () => n, []),
      setStore,
    });
    return store;
  });
  try {
    await act(async () => settle());
    assert.equal(result.current, 1, "first tick applies a found read");
    await act(async () =>
      document.dispatchEvent(new dom.window.Event("visibilitychange")),
    );
    await act(async () => settle());
    assert.equal(
      result.current,
      1,
      "read discarded: revision changed in flight",
    );
    pending = true;
    await act(async () =>
      document.dispatchEvent(new dom.window.Event("visibilitychange")),
    );
    await act(async () => settle());
    assert.equal(fetches, 2, "pending edit skips the read");
  } finally {
    cleanup();
    dom.window.close();
  }
});
