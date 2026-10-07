import assert from "node:assert/strict";
import test from "node:test";
import { relayClient } from "@/shared/api/relayClient";
import { PublishCanceledError } from "@/shared/api/relayEventPublisher";
import {
  resetDetachedToastScope,
  setDetachedToastScope,
} from "@/features/messages/lib/detachedToastScope";
import {
  cancelReminder,
  completeReminder,
  createReminder,
  resetReminderWrites,
  snoozeReminder,
} from "./reminderService.ts";

const pubkey = "a".repeat(64);
const otherPubkey = "b".repeat(64);
const relayUrl = "wss://community.example";
const target = {
  eventId: "message",
  channelId: "channel",
  authorPubkey: "author",
  preview: "Private preview",
};
const reminder = {
  id: "saved-item",
  createdAt: 1000,
  eventId: "previous-event",
  content: { target, status: "pending" },
};
const operations = {
  create: () => createReminder(target, undefined, undefined, undefined, pubkey),
  complete: () => completeReminder(pubkey, reminder),
  snooze: () => snoozeReminder(pubkey, reminder, 2000),
  cancel: () => cancelReminder(pubkey, reminder),
};

function setup(t, beforeCommand = async () => {}) {
  const previousWindow = globalThis.window;
  const commands = [];
  let signer = pubkey;
  globalThis.window = {
    __TAURI_INTERNALS__: {
      invoke: async (command, input) => {
        commands.push(command);
        await beforeCommand(command);
        if (command === "get_identity") return { pubkey: signer };
        if (command === "get_relay_ws_url") return relayUrl;
        if (command === "nip44_encrypt_to_self")
          return `encrypted:${input.plaintext}`;
        if (command === "sign_event")
          return JSON.stringify({
            id: "signed-event",
            pubkey: signer,
            sig: "signature",
            kind: input.kind,
            content: input.content,
            tags: input.tags,
            created_at: input.createdAt,
          });
        throw new Error(command);
      },
    },
  };
  setDetachedToastScope({ relayUrl, signerPubkey: pubkey });
  const publish = t.mock.method(
    relayClient,
    "publishEvent",
    async (event, _timeout, _error, isCurrent) => {
      assert.equal(isCurrent(), true);
      return event;
    },
  );
  t.after(() => {
    globalThis.window = previousWindow;
    resetReminderWrites();
    resetDetachedToastScope();
  });
  return {
    commands,
    publish,
    setSigner: (value) => {
      signer = value;
    },
  };
}

for (const [name, operation] of Object.entries(operations)) {
  test(`${name} publishes under the original signer and community`, async (t) => {
    const { publish } = setup(t);
    assert.equal((await operation()).pubkey, pubkey);
    assert.equal(publish.mock.callCount(), 1);
  });

  for (const phase of [
    "get_identity",
    "get_relay_ws_url",
    "nip44_encrypt_to_self",
    "sign_event",
  ]) {
    test(`${name} cancels after an A to B to A switch during ${phase}`, async (t) => {
      const { commands, publish } = setup(t, async (command) => {
        if (command !== phase) return;
        resetReminderWrites();
        setDetachedToastScope({
          relayUrl: "wss://other.example",
          signerPubkey: otherPubkey,
        });
        resetReminderWrites();
        setDetachedToastScope({ relayUrl, signerPubkey: pubkey });
      });
      await assert.rejects(operation(), PublishCanceledError);
      assert.equal(commands.at(-1), phase);
      assert.equal(publish.mock.callCount(), 0);
    });
  }

  test(`${name} checks the scope again while publication waits`, async (t) => {
    setup(t);
    t.mock.method(
      relayClient,
      "publishEvent",
      async (_event, _timeout, _error, isCurrent) => {
        assert.equal(isCurrent(), true);
        resetReminderWrites();
        assert.equal(isCurrent(), false);
        throw new PublishCanceledError();
      },
    );
    await assert.rejects(operation(), PublishCanceledError);
  });

  test(`${name} rejects a result received after a scope reset`, async (t) => {
    setup(t);
    t.mock.method(relayClient, "publishEvent", async (event) => {
      resetReminderWrites();
      return event;
    });
    await assert.rejects(operation(), PublishCanceledError);
  });
}

test("create rejects a signer changed before the operation starts", async (t) => {
  const { publish, commands, setSigner } = setup(t);
  setSigner(otherPubkey);
  await assert.rejects(operations.create(), PublishCanceledError);
  assert.deepEqual(commands, ["get_identity"]);
  assert.equal(publish.mock.callCount(), 0);
});

for (const scope of [
  null,
  { relayUrl: "wss://other.example", signerPubkey: pubkey },
  { relayUrl, signerPubkey: otherPubkey },
]) {
  test(`create rejects an inactive scope: ${JSON.stringify(scope)}`, async (t) => {
    const { commands, publish } = setup(t);
    if (scope) setDetachedToastScope(scope);
    else resetDetachedToastScope();
    await assert.rejects(operations.create(), PublishCanceledError);
    assert.equal(commands.includes("nip44_encrypt_to_self"), false);
    assert.equal(publish.mock.callCount(), 0);
  });
}

test("create rejects an event signed by a replacement identity", async (t) => {
  const { publish, setSigner } = setup(t, async (command) => {
    if (command === "sign_event") setSigner(otherPubkey);
  });
  await assert.rejects(operations.create(), PublishCanceledError);
  assert.equal(publish.mock.callCount(), 0);
});
