import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import React, { act } from "react";
import { createRoot } from "react-dom/client";

import { ThemeProvider } from "@/shared/theme/ThemeProvider.tsx";
import { TooltipProvider } from "@/shared/ui/tooltip.tsx";
import { buildOlympusUsage } from "../lib/olympusUsage.ts";
import {
  OlympusAgentUsageBlock,
  OlympusUsageTable,
} from "./OlympusUsagePanel.tsx";

window.matchMedia = () => ({
  matches: false,
  addEventListener() {},
  removeEventListener() {},
  addListener() {},
  removeListener() {},
});

const OPERATOR = "b".repeat(64);
const NOW = Math.floor(Date.now() / 1_000);

let id = 1;
function usageEvent(d, content) {
  id += 1;
  return {
    id: id.toString(16).padStart(64, "0"),
    pubkey: OPERATOR,
    kind: 30193,
    created_at: NOW,
    content: JSON.stringify({ v: 1, at: NOW - 120, ...content }),
    tags: [
      ["d", d],
      ["p", "a".repeat(64)],
      ["p", OPERATOR],
      ["status", "active"],
    ],
    sig: "",
  };
}

const STATE = buildOlympusUsage(
  [
    usageEvent("olympus-ops/argus", {
      workspace: "ops",
      namespace: "olympus-ops",
      name: "argus",
      harness: "claude-code",
      windows: {
        "24h": {
          tokens: {
            "claude-opus-5-5": { input: 900_000, output: 300_000 },
            "claude-haiku-5-5": { input: 40_000 },
          },
          turns: 12,
          apiErrors: 0,
          runs: 4,
          failedRuns: 1,
          share: 0.62,
        },
        "7d": {
          tokens: { "claude-opus-5-5": { input: 5_000_000 } },
          turns: 80,
          apiErrors: 2,
          runs: 28,
          failedRuns: 3,
          share: 0.7,
        },
      },
      lastRun: { schedule: "daily-check", at: NOW - 3_600, result: "failed" },
    }),
    usageEvent("olympus-zeus/zeus", {
      workspace: "zeus",
      namespace: "olympus-zeus",
      name: "zeus",
      harness: "claude-code",
      windows: {
        "24h": {
          tokens: { "claude-opus-5-5": { input: 760_000 } },
          turns: 7,
          apiErrors: 0,
          runs: 0,
          failedRuns: 0,
          share: 0.38,
        },
      },
      lastRun: null,
    }),
    usageEvent("hecate", {
      accounts: [
        {
          provider: "claude",
          credential: "max-1",
          window: "5h",
          usedRatio: 0.93,
        },
      ],
    }),
  ],
  new Set([OPERATOR]),
);

let cleanup = [];
afterEach(async () => {
  for (const dispose of cleanup) await dispose();
  cleanup = [];
  document.body.innerHTML = "";
});

async function mount(element) {
  const container = document.createElement("div");
  document.body.append(container);
  const root = createRoot(container);
  const client = new QueryClient({
    defaultOptions: { queries: { enabled: false } },
  });
  await act(async () =>
    root.render(
      React.createElement(
        QueryClientProvider,
        { client },
        React.createElement(
          ThemeProvider,
          null,
          React.createElement(TooltipProvider, null, element),
        ),
      ),
    ),
  );
  cleanup.push(() => act(async () => root.unmount()));
  return container;
}

function Table() {
  const [windowKey, setWindowKey] = React.useState("24h");
  return React.createElement(OlympusUsageTable, {
    accounts: STATE.accounts,
    agents: STATE.agents,
    nowMs: NOW * 1_000,
    onWindowChange: setWindowKey,
    windowKey,
  });
}

function cells(row) {
  return [...row.querySelectorAll("th, td")].map((cell) =>
    cell.textContent.trim(),
  );
}

test("the table shows each agent, the total, and the Hecate quota", async () => {
  const container = await mount(React.createElement(Table));
  const argus = container.querySelector(
    '[data-testid="olympus-usage-row-ops-argus"]',
  );
  assert.deepEqual(cells(argus), [
    "Aargusops · claude-code1h agofailed",
    "1.2M",
    "12",
    "4",
    "1 failed",
    "1h agofailed",
    "62%",
  ]);
  assert.ok(argus.querySelector(".text-destructive svg"));
  const zeus = container.querySelector(
    '[data-testid="olympus-usage-row-zeus-zeus"]',
  );
  assert.deepEqual(cells(zeus).slice(1), ["760k", "7", "0", "0", "–", "38%"]);
  assert.deepEqual(
    cells(container.querySelector('[data-testid="olympus-usage-total"]')),
    ["Total", "2M", "19", "4", "1 failed", "", "100%"],
  );
  const quota = container.querySelector(
    '[data-testid="olympus-usage-accounts"]',
  );
  assert.match(quota.textContent, /claude max-1 · 5h93% used/);
  assert.equal(
    quota.querySelector('[role="progressbar"]').getAttribute("aria-valuenow"),
    "93",
  );
  assert.equal(
    container.textContent.includes("$") || /usd/i.test(container.textContent),
    false,
  );
});

test("the window toggle switches to 7 days", async () => {
  const container = await mount(React.createElement(Table));
  const option = container.querySelector(
    '[data-testid="olympus-usage-window-option-7d"]',
  );
  await act(async () => option.click());
  const argus = container.querySelector(
    '[data-testid="olympus-usage-row-ops-argus"]',
  );
  assert.deepEqual(cells(argus).slice(1, 5), ["5M", "80", "28", "3 failed"]);
});

test("the agent block shows the compact stats", async () => {
  const container = await mount(
    React.createElement(OlympusAgentUsageBlock, {
      agents: STATE.agents,
      nowMs: NOW * 1_000,
      onWindowChange: () => {},
      usage: STATE.agents[0],
      windowKey: "24h",
    }),
  );
  const stats = [...container.querySelectorAll("dl > div")].map((node) =>
    node.textContent.trim(),
  );
  assert.deepEqual(stats, [
    "Tokens1.2M",
    "Turns12",
    "Runs4",
    "Failed1 failed",
    "Share62%",
    "API errors0",
  ]);
  assert.match(container.textContent, /claude-opus-5-51\.2M/);
  assert.match(container.textContent, /claude-haiku-5-540k/);
});
