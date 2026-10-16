import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import * as React from "react";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";

import { CustomTabPanel } from "./CustomTabPanel.tsx";

let root;
let container;

async function render(tab) {
  container = document.createElement("div");
  document.body.appendChild(container);
  root = createRoot(container);
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false, enabled: false } },
  });
  await act(async () =>
    root.render(
      React.createElement(
        QueryClientProvider,
        { client },
        React.createElement(CustomTabPanel, {
          tab,
          channelId: "c",
          canEditCanvas: false,
          onOpenMessage: () => {},
          onOpenThread: () => {},
        }),
      ),
    ),
  );
}

afterEach(async () => {
  await act(async () => root.unmount());
  container.remove();
});

test("a link tab embeds the https page in a sandboxed frame", async () => {
  await render({
    id: "g",
    type: "link",
    title: "Grafana",
    value: "https://grafana.xqx.uk",
  });
  const frame = container.querySelector("iframe");
  assert.equal(frame.getAttribute("src"), "https://grafana.xqx.uk");
  assert.equal(
    frame.getAttribute("sandbox"),
    "allow-scripts allow-same-origin allow-forms allow-popups",
  );
  assert.equal(frame.getAttribute("referrerpolicy"), "no-referrer");
  assert.ok(container.querySelector('[data-testid="custom-tab-open-browser"]'));
});

test("an invalid link value never reaches a frame", async () => {
  await render({
    id: "x",
    type: "link",
    title: "Bad",
    value: "javascript:alert(1)",
  });
  assert.equal(container.querySelector("iframe"), null);
  assert.ok(container.querySelector('[data-testid="custom-tab-invalid"]'));
});

test("a link tab frames the trimmed URL", async () => {
  await render({
    id: "g",
    type: "link",
    title: "Grafana",
    value: "  https://grafana.xqx.uk  ",
  });
  assert.equal(
    container.querySelector("iframe").getAttribute("src"),
    "https://grafana.xqx.uk",
  );
  assert.equal(
    container
      .querySelector('[data-testid="custom-tab-link"]')
      .textContent.includes("  https"),
    false,
  );
});
