import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import React, { act } from "react";
import { createRoot } from "react-dom/client";
import { HuddleProvider, useHuddle } from "./HuddleContext.tsx";

const handlers = new Map();
const listeners = new Map();
const calls = [];
let callbackId = 0;
const callbacks = new Map();
const tauriMock = {
  transformCallback(callback) {
    const id = ++callbackId;
    callbacks.set(id, callback);
    return id;
  },
  unregisterCallback(id) {
    callbacks.delete(id);
  },
  async invoke(command, args) {
    calls.push(command);
    if (command === "plugin:event|listen") {
      listeners.set(args.handler, args.event);
      return args.handler;
    }
    if (command === "plugin:event|unlisten") {
      listeners.delete(args.eventId);
      return;
    }
    if (handlers.has(command)) return handlers.get(command)(args);
    if (command === "get_huddle_state") return { phase: "idle" };
    if (command === "get_voice_input_mode") return "voice_activity";
    if (command === "get_identity") return { pubkey: "ef".repeat(32) };
    if (command === "get_huddle_agent_pubkeys") return [];
    if (command === "list_audio_output_devices") return [];
    if (command === "get_audio_output_device") return "";
  },
};
window.__TAURI_INTERNALS__ = tauriMock;
globalThis.__TAURI_INTERNALS__ = tauriMock;
window.__TAURI_EVENT_PLUGIN_INTERNALS__ = {
  unregisterListener: (_event, id) => listeners.delete(id),
};
Object.defineProperty(navigator, "mediaDevices", {
  configurable: true,
  value: Object.assign(new EventTarget(), {
    enumerateDevices: async () => [],
    getUserMedia: async () => new MediaStream([track]),
  }),
});
const track = {
  enabled: true,
  stops: 0,
  stop() {
    this.stops += 1;
  },
};
const audioContexts = [];
const node = () => ({ connect() {}, disconnect() {}, gain: { value: 1 } });
globalThis.MediaStream = class {
  constructor(tracks) {
    this.tracks = tracks;
  }
  getAudioTracks() {
    return this.tracks;
  }
  getTracks() {
    return this.tracks;
  }
};
globalThis.AudioContext = class {
  state = "running";
  audioWorklet = { addModule: async () => {} };
  constructor() {
    audioContexts.push(this);
  }
  createMediaStreamSource() {
    return node();
  }
  createGain() {
    return node();
  }
  createAnalyser() {
    return { ...node(), fftSize: 512, getFloatTimeDomainData() {} };
  }
  async close() {
    this.state = "closed";
  }
};
globalThis.AudioWorkletNode = class {
  port = { postMessage() {}, onmessage: null };
  disconnect() {}
};
globalThis.requestAnimationFrame = () => 1;
globalThis.cancelAnimationFrame = () => {};

let root;
let container;
let huddle;
function CaptureHuddle() {
  huddle = useHuddle();
  return null;
}
async function mount() {
  container = document.createElement("div");
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () =>
    root.render(
      React.createElement(
        HuddleProvider,
        {},
        React.createElement(CaptureHuddle),
      ),
    ),
  );
}
async function deliverState(payload) {
  await act(async () => {
    for (const [id, event] of [...listeners]) {
      if (event === "huddle-state-changed") {
        callbacks.get(id)?.({ event, id, payload });
      }
    }
  });
}
afterEach(async () => {
  if (root) await act(async () => root.unmount());
  container?.remove();
  root = null;
  huddle = null;
  handlers.clear();
  listeners.clear();
  callbacks.clear();
  calls.length = 0;
  audioContexts.length = 0;
  track.stops = 0;
});

test("a companion leave stops browser capture before relay cleanup completes", async () => {
  handlers.set("join_huddle", () => ({ ephemeral_channel_id: "room" }));
  handlers.set("leave_huddle", () => new Promise(() => {}));
  await mount();
  await act(async () => huddle.joinHuddle("parent", "room"));
  assert.equal(huddle.micConnected, true);
  assert.equal(track.stops, 0);

  void tauriMock.invoke("leave_huddle");
  await deliverState({ phase: "leaving", ephemeral_channel_id: "room" });

  assert.equal(track.stops, 1);
  assert.equal(huddle.micConnected, false);
  assert.equal(huddle.activeEphemeralChannelId, null);
  assert.ok(audioContexts.length >= 2);
  assert.ok(audioContexts.every((context) => context.state === "closed"));
});

test("a delayed initial backend snapshot cannot restore a leaving huddle", async () => {
  let resolveSnapshot;
  handlers.set(
    "get_huddle_state",
    () =>
      new Promise((resolve) => {
        resolveSnapshot = resolve;
      }),
  );
  await mount();
  await deliverState({ phase: "leaving", ephemeral_channel_id: "room" });
  const hotstartsBeforeSnapshot = calls.filter(
    (command) => command === "check_pipeline_hotstart",
  ).length;

  await act(async () =>
    resolveSnapshot({
      phase: "active",
      ephemeral_channel_id: "room",
    }),
  );

  assert.equal(huddle.activeEphemeralChannelId, null);
  assert.equal(
    calls.filter((command) => command === "check_pipeline_hotstart").length,
    hotstartsBeforeSnapshot,
  );
});
