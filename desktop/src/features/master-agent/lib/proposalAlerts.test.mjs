import assert from "node:assert/strict";
import test from "node:test";

import {
  EMPTY_PROPOSAL_ALERT_LEDGER,
  loadProposalAlertLedger,
  planProposalAlerts,
  PROPOSAL_SOON_SECONDS,
  proposalAlertText,
  recordProposalAlert,
  saveProposalAlertLedger,
} from "./proposalAlerts.ts";

const OPERATOR = "b".repeat(64);
const NOW = 1_000_000;

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
    reason: "Argus is idle.\n  Suspend it to save tokens.",
    diff: [],
    diffTruncated: false,
    highRisk: [],
    createdAt: NOW - 60,
    expiresAt: NOW + 86_000,
    digest: "d".repeat(64),
    phase: "pending",
    result: null,
    ...overrides,
  };
}

function names(plan) {
  return plan.alerts.map((alert) => `${alert.kind}:${alert.proposal.name}`);
}

function replay(proposals, now, ledger = EMPTY_PROPOSAL_ALERT_LEDGER) {
  let next = ledger;
  const plan = planProposalAlerts(proposals, now, next);
  for (const alert of plan.alerts) next = recordProposalAlert(next, alert, now);
  return { plan, ledger: next };
}

test("one alert for each new open proposal, none for decided or expired ones", () => {
  const proposals = [
    proposal("p-new"),
    proposal("p-applied", { phase: "applied" }),
    proposal("p-gone", { expiresAt: NOW - 1 }),
  ];
  const first = replay(proposals, NOW);
  assert.deepEqual(names(first.plan), ["new:p-new"]);
  assert.equal(first.plan.nextCheckAt, NOW + 86_000 - PROPOSAL_SOON_SECONDS);
  const again = replay(proposals, NOW + 10, first.ledger);
  assert.deepEqual(names(again.plan), []);
});

test("one more alert when less than 2 h remain, and only once", () => {
  const item = proposal("p-1");
  const { ledger } = replay([item], NOW);
  const soonAt = item.expiresAt - PROPOSAL_SOON_SECONDS;
  assert.deepEqual(names(replay([item], soonAt - 1, ledger).plan), []);
  const warned = replay([item], soonAt, ledger);
  assert.deepEqual(names(warned.plan), ["soon:p-1"]);
  assert.equal(warned.plan.nextCheckAt, null);
  assert.deepEqual(names(replay([item], soonAt + 60, warned.ledger).plan), []);
});

test("a new proposal that already expires soon gets one alert, not two", () => {
  const item = proposal("p-late", { expiresAt: NOW + 600 });
  const first = replay([item], NOW);
  assert.deepEqual(names(first.plan), ["new:p-late"]);
  assert.deepEqual(names(replay([item], NOW + 60, first.ledger).plan), []);
});

test("an unsent alert stays planned", () => {
  const item = proposal("p-1");
  const plan = planProposalAlerts([item], NOW, EMPTY_PROPOSAL_ALERT_LEDGER);
  assert.deepEqual(names(plan), ["new:p-1"]);
  assert.deepEqual(
    names(planProposalAlerts([item], NOW + 5, EMPTY_PROPOSAL_ALERT_LEDGER)),
    ["new:p-1"],
  );
});

test("the ledger survives a restart per identity and is bounded", () => {
  const store = new Map();
  const storage = {
    getItem: (key) => store.get(key) ?? null,
    setItem: (key, value) => store.set(key, value),
  };
  const { ledger } = replay([proposal("p-1")], NOW);
  saveProposalAlertLedger(storage, "me", ledger);
  assert.deepEqual(loadProposalAlertLedger(storage, "me"), ledger);
  assert.deepEqual(
    loadProposalAlertLedger(storage, "other"),
    EMPTY_PROPOSAL_ALERT_LEDGER,
  );
  store.set("buzz.olympus.proposal-alerts.v1:bad", "{nope");
  assert.deepEqual(
    loadProposalAlertLedger(storage, "bad"),
    EMPTY_PROPOSAL_ALERT_LEDGER,
  );

  let big = EMPTY_PROPOSAL_ALERT_LEDGER;
  for (let index = 0; index < 600; index += 1) {
    big = recordProposalAlert(
      big,
      { kind: "new", proposal: proposal(`p-${index}`) },
      NOW,
    );
  }
  assert.equal(big.new.length, 500);
  assert.equal(big.new.at(-1), `proposal:${OPERATOR}:p-599`);
});

test("alert text names the requester, the change, and the risk", () => {
  const item = proposal("p-1", { highRisk: ["secrets"] });
  assert.deepEqual(
    proposalAlertText({ kind: "new", proposal: item }, "Zeus", NOW),
    {
      title: "Zeus asks for approval",
      body: "High risk · patch Agent argus in ops · Argus is idle. Suspend it to save tokens.",
    },
  );
  assert.deepEqual(
    proposalAlertText(
      { kind: "soon", proposal: item },
      "Zeus",
      item.expiresAt - 95 * 60,
    ),
    {
      title: "Approval expires in 1 h 35 min",
      body: "High risk · Zeus: patch Agent argus in ops",
    },
  );
});
