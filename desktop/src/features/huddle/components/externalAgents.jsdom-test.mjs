import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import React, { act } from "react";
import { createRoot } from "react-dom/client";
import { ThemeProvider } from "@/shared/theme/ThemeProvider";
import { HuddleProvider, useHuddle } from "../HuddleContext.tsx";
import { AddAgentDialog } from "./AddAgentDialog.tsx";

const hermes = "ab".repeat(32);
const fizz = "cd".repeat(32);
const owner = "ef".repeat(32);
const handlers = new Map();
const calls = [];
const tauriMock = {
  invoke(command, args) {
    calls.push({ command, args });
    const handler = handlers.get(command);
    return handler
      ? Promise.resolve().then(() => handler(args))
      : new Promise(() => {});
  },
  transformCallback: () => 1,
  unregisterCallback: () => {},
};
globalThis.window.__TAURI_INTERNALS__ = tauriMock;
globalThis.__TAURI_INTERNALS__ = tauriMock;
window.matchMedia = () => ({
  matches: false,
  addEventListener() {},
  removeEventListener() {},
});
Object.defineProperty(navigator, "mediaDevices", {
  configurable: true,
  value: Object.assign(new EventTarget(), { enumerateDevices: async () => [] }),
});

let root;
let container;
afterEach(async () => {
  if (root) await act(async () => root.unmount());
  container?.remove();
  root = null;
  handlers.clear();
  calls.length = 0;
});

async function mount(element) {
  container = document.createElement("div");
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () => root.render(element));
}

function members() {
  return {
    members: [
      { pubkey: owner, role: "owner", is_agent: false, display_name: "Owner" },
      { pubkey: hermes, role: "bot", is_agent: false, display_name: "Hermes" },
      {
        pubkey: fizz.toUpperCase(),
        role: "bot",
        is_agent: true,
        display_name: "Fizz",
      },
    ],
  };
}

async function mountDialog(currentAgentPubkeys = []) {
  const added = [];
  handlers.set("list_managed_agents", () => [
    {
      pubkey: fizz,
      name: "Fizz",
      status: "stopped",
      avatar_url: null,
      backend: { type: "local" },
    },
  ]);
  if (!handlers.has("get_channel_members"))
    handlers.set("get_channel_members", members);
  handlers.set("start_managed_agent", () => undefined);
  await mount(
    React.createElement(
      ThemeProvider,
      {},
      React.createElement(AddAgentDialog, {
        open: true,
        parentChannelId: "parent",
        currentAgentPubkeys,
        onClose() {},
        onAdd: async (pubkey) => {
          added.push(pubkey);
          return {
            ephemeral_added: true,
            parent_added: false,
            parent_error: null,
          };
        },
      }),
    ),
  );
  return added;
}

function agentButton(name) {
  return [...document.querySelectorAll("button")].find((button) =>
    button.textContent.endsWith(name),
  );
}

test("channel bots appear once and use existing external identities", async () => {
  const added = await mountDialog();
  assert.ok(agentButton("Hermes"));
  assert.equal(
    [...document.querySelectorAll("button")].filter((button) =>
      button.textContent.endsWith("Fizz"),
    ).length,
    1,
  );
  assert.equal(agentButton("Owner"), undefined);
  await act(async () => agentButton("Hermes").click());
  assert.deepEqual(added, [hermes]);
  assert.equal(
    calls.some(
      ({ command }) =>
        command === "start_managed_agent" || command === "stop_managed_agent",
    ),
    false,
  );
  await act(async () => agentButton("Fizz").click());
  assert.deepEqual(added, [hermes, fizz]);
  assert.equal(
    calls.filter(({ command }) => command === "start_managed_agent").length,
    1,
  );
});

test("already enrolled external agents are hidden", async () => {
  await mountDialog([hermes.toUpperCase()]);
  assert.equal(agentButton("Hermes"), undefined);
  assert.ok(agentButton("Fizz"));
});

test("channel discovery failure retains managed agents and displays an error", async () => {
  handlers.set("get_channel_members", () => {
    throw new Error("offline");
  });
  await mountDialog();
  assert.ok(agentButton("Fizz"));
  assert.match(document.body.textContent, /Could not load all agents/);
});

test("every huddle start enrolls channel bots and deduplicates requested agents", async () => {
  let huddle;
  function CaptureHuddle() {
    huddle = useHuddle();
    return null;
  }
  handlers.set("get_channel_members", members);
  handlers.set("start_huddle", () => {
    throw new Error("captured start");
  });
  await mount(
    React.createElement(HuddleProvider, {}, React.createElement(CaptureHuddle)),
  );
  await act(async () => {
    await assert.rejects(
      huddle.startHuddle("parent", [fizz], "Test huddle"),
      /captured start/,
    );
  });
  const start = calls.find(({ command }) => command === "start_huddle");
  assert.deepEqual(start.args, {
    parentChannelId: "parent",
    memberPubkeys: [fizz, hermes],
    channelName: "Test huddle",
  });
  assert.equal(
    calls.some(({ command }) => command === "start_managed_agent"),
    false,
  );
});

test("huddle start reports failed channel discovery before channel creation", async () => {
  let huddle;
  function CaptureHuddle() {
    huddle = useHuddle();
    return null;
  }
  handlers.set("get_channel_members", () => {
    throw new Error("offline");
  });
  await mount(
    React.createElement(HuddleProvider, {}, React.createElement(CaptureHuddle)),
  );
  await act(async () => {
    await assert.rejects(huddle.startHuddle("parent", []), /offline/);
  });
  assert.equal(
    calls.some(({ command }) => command === "start_huddle"),
    false,
  );
  assert.ok(huddle.huddleError);
});
