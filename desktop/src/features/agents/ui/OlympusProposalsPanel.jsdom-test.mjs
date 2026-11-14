import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import React, { act } from "react";
import { createRoot } from "react-dom/client";

import { ThemeProvider } from "@/shared/theme/ThemeProvider.tsx";
import { resetOlympusChangeRequests } from "../lib/olympusChangeRequests.ts";
import { OlympusProposalCard } from "./OlympusProposalCard.tsx";
import { OlympusProposalsList } from "./OlympusProposalsPanel.tsx";

window.matchMedia = () => ({
  matches: false,
  addEventListener() {},
  removeEventListener() {},
  addListener() {},
  removeListener() {},
});

const OPERATOR = "b".repeat(64);
const NOW = Math.floor(Date.now() / 1_000);

function proposal(name, overrides = {}) {
  return {
    author: OPERATOR,
    eventId: "1".repeat(64),
    name,
    workspace: "ops",
    requester: "zeus/zeus",
    requesterKey: "9".repeat(64),
    target: { kind: "Agent", namespace: "olympus-ops", name: "argus" },
    operation: "patch",
    reason: "Argus is idle.",
    diff: [{ path: "spec.suspend", from: "false", to: "true" }],
    diffTruncated: false,
    highRisk: [],
    createdAt: NOW - 600,
    expiresAt: NOW + 80_000,
    digest: "d".repeat(64),
    phase: "pending",
    result: null,
    ...overrides,
  };
}

const PROPOSALS = [
  proposal("p-open"),
  proposal("p-late", { createdAt: NOW - 90_000, expiresAt: NOW - 60 }),
  proposal("p-applied", {
    createdAt: NOW - 300,
    phase: "applied",
    result: { reason: "applied", request: "f".repeat(64), at: NOW - 7_200 },
  }),
  proposal("p-rejected", {
    createdAt: NOW - 100,
    phase: "rejected",
    result: {
      reason: "rejected by the owner: keep Argus running",
      request: "e".repeat(64),
      at: NOW - 60,
    },
  }),
];

let cleanup = [];
afterEach(async () => {
  for (const dispose of cleanup) await dispose();
  cleanup = [];
  resetOlympusChangeRequests();
  document.body.innerHTML = "";
});

async function mount(element) {
  const container = document.createElement("div");
  document.body.append(container);
  const root = createRoot(container);
  await act(async () =>
    root.render(React.createElement(ThemeProvider, null, element)),
  );
  cleanup.push(() => act(async () => root.unmount()));
  return { container };
}

function byTestId(container, id) {
  return container.querySelector(`[data-testid="${id}"]`);
}

async function click(element) {
  await act(async () => {
    element.dispatchEvent(
      new window.MouseEvent("pointerdown", { bubbles: true }),
    );
    element.dispatchEvent(
      new window.MouseEvent("mousedown", { bubbles: true }),
    );
    element.click();
  });
}

function List({ initial = "all" }) {
  const [filter, setFilter] = React.useState(initial);
  return React.createElement(OlympusProposalsList, {
    filter,
    now: NOW,
    onFilterChange: setFilter,
    proposals: PROPOSALS,
    submitChange: async () => {},
  });
}

test("filter chips show counts and switch the list", async () => {
  const { container } = await mount(React.createElement(List));
  const chip = (name) => byTestId(container, `olympus-proposal-filter-${name}`);
  assert.equal(chip("pending").textContent, "Pending1");
  assert.equal(chip("expired").textContent, "Expired1");
  assert.equal(chip("applied").getAttribute("aria-pressed"), "false");
  assert.equal(chip("all").getAttribute("aria-pressed"), "true");
  const names = () =>
    [...container.querySelectorAll('[data-testid^="olympus-proposal-p-"]')].map(
      (node) => node.dataset.testid.replace("olympus-proposal-", ""),
    );
  assert.deepEqual(names(), ["p-rejected", "p-applied", "p-open", "p-late"]);

  await click(chip("expired"));
  assert.deepEqual(names(), ["p-late"]);
  assert.equal(chip("expired").getAttribute("aria-pressed"), "true");

  await click(chip("failed"));
  assert.deepEqual(names(), []);
  assert.equal(
    byTestId(container, "olympus-proposals-empty").textContent,
    "No failed proposals.Show all 4 proposals",
  );
  await click(byTestId(container, "olympus-proposals-show-all"));
  assert.equal(chip("all").getAttribute("aria-pressed"), "true");
  assert.equal(names().length, 4);
});

test("the pending filter with no open proposal links to all proposals", async () => {
  const decided = PROPOSALS.filter((item) => item.name !== "p-open");
  function PendingList() {
    const [filter, setFilter] = React.useState("pending");
    return React.createElement(OlympusProposalsList, {
      filter,
      now: NOW,
      onFilterChange: setFilter,
      proposals: decided,
      submitChange: async () => {},
    });
  }
  const { container } = await mount(React.createElement(PendingList));
  const empty = byTestId(container, "olympus-proposals-empty");
  assert.match(empty.textContent, /Nothing waits for your decision/);
  await click(byTestId(container, "olympus-proposals-show-all"));
  assert.equal(
    byTestId(container, "olympus-proposal-filter-all").getAttribute(
      "aria-pressed",
    ),
    "true",
  );
  assert.equal(
    container.querySelectorAll('[data-testid^="olympus-proposal-p-"]').length,
    decided.length,
  );
});

test("a decided proposal shows its result reason and decided time, no buttons", async () => {
  const { container } = await mount(
    React.createElement(List, { initial: "rejected" }),
  );
  const card = byTestId(container, "olympus-proposal-p-rejected");
  assert.equal(
    byTestId(card, "olympus-proposal-result").textContent,
    "Result:rejected by the owner: keep Argus running· decided 1m ago",
  );
  assert.equal(
    byTestId(card, "olympus-proposal-phase").textContent,
    "rejected",
  );
  assert.equal(card.querySelectorAll("button").length, 0);
});

test("reject opens a dialog and sends the trimmed reason", async () => {
  const calls = [];
  const { container } = await mount(
    React.createElement(OlympusProposalCard, {
      proposal: proposal("p-open"),
      submitChange: async (...args) => {
        calls.push(args);
      },
    }),
  );
  const reject = [...container.querySelectorAll("button")].find(
    (button) => button.textContent === "Reject",
  );
  await click(reject);
  assert.equal(calls.length, 0);
  const dialog = byTestId(document.body, "olympus-reject-dialog");
  assert.ok(dialog);
  const textarea = byTestId(dialog, "olympus-reject-reason");
  assert.equal(textarea.getAttribute("maxlength"), "1000");
  await act(async () => {
    const setter = Object.getOwnPropertyDescriptor(
      window.HTMLTextAreaElement.prototype,
      "value",
    ).set;
    setter.call(textarea, "  Keep Argus running  ");
    textarea.dispatchEvent(new window.Event("input", { bubbles: true }));
  });
  assert.equal(
    byTestId(dialog, "olympus-reject-counter").textContent,
    "18/1000",
  );
  const submit = [...dialog.querySelectorAll("button")].find(
    (button) => button.textContent === "Reject proposal",
  );
  await click(submit);
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0][2], {
    action: "reject",
    proposal: "p-open",
    digest: "d".repeat(64),
    reason: "Keep Argus running",
  });
  assert.equal(byTestId(document.body, "olympus-reject-dialog"), null);
});

test("reject without a reason sends no reason field", async () => {
  const calls = [];
  const { container } = await mount(
    React.createElement(OlympusProposalCard, {
      proposal: proposal("p-open"),
      submitChange: async (...args) => {
        calls.push(args);
      },
    }),
  );
  await click(
    [...container.querySelectorAll("button")].find(
      (button) => button.textContent === "Reject",
    ),
  );
  const dialog = byTestId(document.body, "olympus-reject-dialog");
  await click(
    [...dialog.querySelectorAll("button")].find(
      (button) => button.textContent === "Reject proposal",
    ),
  );
  assert.deepEqual(calls[0][2], {
    action: "reject",
    proposal: "p-open",
    digest: "d".repeat(64),
  });
});

test("short values stay on one line with markers; long values get a line diff", async () => {
  const { container } = await mount(
    React.createElement(OlympusProposalCard, {
      proposal: proposal("p-diff", {
        diff: [
          { path: "spec.suspend", from: "false", to: "true" },
          {
            path: "spec.instructions",
            from: JSON.stringify(
              "You are Argus.\nWatch the cluster.\nBe brief.",
            ),
            to: JSON.stringify(
              "You are Argus.\nWatch the cluster and the NAS.\nBe brief.",
            ),
          },
        ],
      }),
      submitChange: async () => {},
    }),
  );
  const diff = byTestId(container, "olympus-proposal-diff");
  const short = diff.querySelector("li");
  assert.equal(short.querySelector("del").textContent, "-false");
  assert.equal(short.querySelector("ins").textContent, "+true");
  const lines = [
    ...byTestId(diff, "olympus-proposal-line-diff").querySelectorAll(
      "[data-line]",
    ),
  ].map((line) => `${line.dataset.line}|${line.lastElementChild.textContent}`);
  assert.deepEqual(lines, [
    "same|You are Argus.",
    "del|Watch the cluster.",
    "add|Watch the cluster and the NAS.",
    "same|Be brief.",
  ]);
});
