import assert from "node:assert/strict";
import test, { mock } from "node:test";
import { relayClient } from "@/shared/api/relayClient";
import {
  resetDetachedToastScope,
  setDetachedToastScope,
} from "@/features/messages/lib/detachedToastScope";
import {
  createReminder,
  completeReminder,
  cancelReminder,
  snoozeReminder,
  fetchReminders,
  resetReminderWrites,
} from "./reminderService.ts";
import { countDue } from "./reminderFilters.ts";

test("Later saves privately without a due time, then completes, archives and restores the same item", async (t) => {
  const previousWindow = globalThis.window;
  const events = [];
  globalThis.window = {
    __TAURI_INTERNALS__: {
      invoke: async (command, input) => {
        if (command === "get_identity") return { pubkey: "me" };
        if (command === "get_relay_ws_url") return "wss://community.example";
        if (command === "nip44_encrypt_to_self")
          return `encrypted:${input.plaintext}`;
        if (command === "nip44_decrypt_from_self")
          return input.ciphertext.slice(10);
        if (command === "sign_event")
          return JSON.stringify({
            id: `event-${events.length}`,
            pubkey: "me",
            sig: "signature",
            kind: input.kind,
            content: input.content,
            tags: input.tags,
            created_at: input.createdAt ?? 1000,
          });
        throw new Error(command);
      },
    },
  };
  setDetachedToastScope({
    relayUrl: "wss://community.example",
    signerPubkey: "me",
  });
  t.after(() => {
    mock.restoreAll();
    globalThis.window = previousWindow;
    resetReminderWrites();
    resetDetachedToastScope();
  });
  mock.method(relayClient, "publishEvent", async (event) => {
    events.push(event);
    return event;
  });
  mock.method(relayClient, "fetchEvents", async (filter) => {
    assert.deepEqual(filter.authors, ["me"]);
    return [events.at(-1)];
  });
  const target = {
    eventId: "message",
    channelId: "channel",
    authorPubkey: "author",
    preview: "File and link",
  };
  await createReminder(target);
  const id = events[0].tags[0][1];
  assert.match(id, /^[0-9a-f]{32}$/);
  assert.deepEqual(events[0].tags, [["d", id]]);
  assert.equal(events[0].kind, 30300);
  assert.match(events[0].content, /^encrypted:/);
  let [item] = await fetchReminders("me");
  const original = item;
  assert.deepEqual(item.content.target, target);
  assert.equal(countDue([item]), 0);
  await completeReminder("me", item);
  [item] = await fetchReminders("me");
  assert.equal(item.content.status, "done");
  assert.deepEqual(events.at(-1).tags, [["d", id]]);
  await cancelReminder("me", original);
  [item] = await fetchReminders("me");
  assert.equal(item.content.status, "cancelled");
  assert.deepEqual(events.at(-1).tags, [["d", id]]);
  await snoozeReminder("me", original);
  [item] = await fetchReminders("me");
  assert.equal(item.content.status, "pending");
  assert.equal(item.notBefore, undefined);
  await snoozeReminder("me", item, 2000);
  [item] = await fetchReminders("me");
  assert.equal(item.notBefore, 2000);
  assert.equal(countDue([item], 2000), 1);
  await createReminder(target, undefined, undefined, original);
  assert.deepEqual(events.at(-1).tags, [["d", id]]);
  assert.ok(
    events.every(
      (event, index) =>
        index === 0 || event.created_at > events[index - 1].created_at,
    ),
  );
  mock.method(relayClient, "publishEvent", async () => {
    throw new Error("relay unavailable");
  });
  await assert.rejects(createReminder(target), /relay unavailable/);
});
