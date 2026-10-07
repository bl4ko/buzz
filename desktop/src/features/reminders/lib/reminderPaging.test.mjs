import assert from "node:assert/strict";
import test, { mock } from "node:test";
import { relayClient } from "@/shared/api/relayClient";
import { fetchReminders } from "./reminderService.ts";

function event(
  index,
  createdAt = index + 1,
  id = `item-${index}`,
  note = "Saved item",
) {
  return {
    id: String(index).padStart(6, "0"),
    pubkey: "me",
    kind: 30300,
    created_at: createdAt,
    tags: [["d", id]],
    sig: "signature",
    content: JSON.stringify({ status: "pending", note }),
  };
}

function setup(t, events, failOnCall) {
  const previousWindow = globalThis.window;
  const calls = [];
  globalThis.window = {
    __TAURI_INTERNALS__: {
      invoke: async (command, input) => {
        assert.equal(command, "nip44_decrypt_from_self");
        return input.ciphertext;
      },
    },
  };
  t.after(() => {
    mock.restoreAll();
    globalThis.window = previousWindow;
  });
  mock.method(relayClient, "fetchEvents", async (filter) => {
    calls.push(filter);
    assert.deepEqual(filter.authors, ["me"]);
    assert.deepEqual(filter.kinds, [30300]);
    assert.ok(calls.length <= 30, "paging must terminate");
    if (calls.length === failOnCall) throw new Error("relay unavailable");
    return events
      .filter(
        (item) => filter.until === undefined || item.created_at <= filter.until,
      )
      .sort((a, b) => b.created_at - a.created_at || a.id.localeCompare(b.id))
      .slice(0, Math.min(filter.limit, 1000));
  });
  return calls;
}

test("saved item recovery pages past 200 records without duplicates", async (t) => {
  const calls = setup(
    t,
    Array.from({ length: 1350 }, (_, index) => event(index)),
  );
  const items = await fetchReminders("me");
  assert.equal(items.length, 1350);
  assert.equal(new Set(items.map((item) => item.id)).size, 1350);
  assert.ok(items.some((item) => item.id === "item-0"));
  assert.ok(calls.length > 1);
});

test("dense timestamps expand the page and keep the newest replacement", async (t) => {
  const events = Array.from({ length: 600 }, (_, index) => event(index, 1000));
  events.push(
    ...Array.from({ length: 201 }, (_, index) => event(index + 600, index + 1)),
  );
  events.push(event(900, 999, "item-0", "Old version"));
  events.push(event(901, 1000, "item-1", "Same-time losing version"));
  const calls = setup(t, events);
  const items = await fetchReminders("me");
  assert.equal(items.length, 801);
  assert.equal(
    items.find((item) => item.id === "item-0").content.note,
    "Saved item",
  );
  assert.equal(items.find((item) => item.id === "item-1").eventId, "000001");
  assert.ok(calls.some((filter) => filter.limit === 1000));
});

test("saturated timestamp reports an error instead of partial results", async (t) => {
  const calls = setup(
    t,
    Array.from({ length: 1001 }, (_, index) => event(index, 1000)),
  );
  await assert.rejects(
    fetchReminders("me"),
    /full relay page shares one timestamp/,
  );
  assert.ok(calls.length <= 4);
});

test("a failed next page cannot return a partial saved list", async (t) => {
  setup(
    t,
    Array.from({ length: 250 }, (_, index) => event(index)),
    2,
  );
  await assert.rejects(fetchReminders("me"), /relay unavailable/);
});
