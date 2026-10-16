import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import * as React from "react";
import { act } from "react";
import { createRoot } from "react-dom/client";

import { ThemeProvider } from "@/shared/theme/ThemeProvider";
import { AddChannelTabDialog } from "./AddChannelTabDialog.tsx";

window.matchMedia = () => ({
  matches: false,
  addEventListener() {},
  removeEventListener() {},
  addListener() {},
  removeListener() {},
});

let root;
let container;
let submitted;

async function render(initial = null) {
  submitted = [];
  container = document.createElement("div");
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () =>
    root.render(
      React.createElement(
        ThemeProvider,
        null,
        React.createElement(AddChannelTabDialog, {
          open: true,
          initial,
          onOpenChange: () => {},
          onSubmit: async (tab) => submitted.push(tab),
        }),
      ),
    ),
  );
}

afterEach(async () => {
  await act(async () => root.unmount());
  container.remove();
});

const byId = (id) => document.body.querySelector(`[data-testid="${id}"]`);

async function type(id, value) {
  const input = byId(id);
  await act(async () => {
    const setter = Object.getOwnPropertyDescriptor(
      window.HTMLInputElement.prototype,
      "value",
    ).set;
    setter.call(input, value);
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
}

test("a link tab needs a title and an https URL", async () => {
  await render();
  await type("tab-title", "Grafana");
  await type("tab-value", "http://grafana.xqx.uk");
  await act(async () => byId("tab-submit").click());
  assert.equal(submitted.length, 0);
  assert.match(byId("tab-error").textContent, /https/);
  await type("tab-value", "https://grafana.xqx.uk");
  await act(async () => byId("tab-submit").click());
  assert.equal(submitted[0].type, "link");
  assert.equal(submitted[0].value, "https://grafana.xqx.uk");
  assert.match(submitted[0].id, /^[A-Za-z0-9_-]{1,64}$/);
});

test("a canvas tab gets a generated canvas id and rename keeps id and value", async () => {
  await render();
  await act(async () => byId("tab-type-canvas").click());
  assert.equal(byId("tab-value"), null);
  await type("tab-title", "Runbook");
  await act(async () => byId("tab-submit").click());
  assert.match(submitted[0].value, /^[A-Za-z0-9_-]{1,64}$/);
  await act(async () => root.unmount());
  container.remove();
  await render({
    id: "t1",
    type: "link",
    title: "Old",
    value: "https://a.example",
  });
  await type("tab-title", "New");
  await act(async () => byId("tab-submit").click());
  assert.deepEqual(submitted[0], {
    id: "t1",
    type: "link",
    title: "New",
    value: "https://a.example",
  });
});

test("a failed save keeps the dialog open with the input and shows an error", async () => {
  submitted = [];
  container = document.createElement("div");
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () =>
    root.render(
      React.createElement(
        ThemeProvider,
        null,
        React.createElement(AddChannelTabDialog, {
          open: true,
          initial: null,
          onOpenChange: () => {},
          onSubmit: async () => {
            throw new Error("offline");
          },
        }),
      ),
    ),
  );
  await type("tab-title", "Grafana");
  await type("tab-value", "https://grafana.xqx.uk");
  await act(async () => byId("tab-submit").click());
  assert.match(byId("tab-error").textContent, /Couldn't save/);
  assert.equal(byId("tab-title").value, "Grafana");
  assert.equal(byId("tab-value").value, "https://grafana.xqx.uk");
});
