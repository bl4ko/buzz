import { expect, type Page, test } from "@playwright/test";

import { installMockBridge } from "../helpers/bridge";
import {
  OLYMPUS_OPERATOR,
  OLYMPUS_OWNER,
  olympusDevEvents,
  olympusHecateEvent,
  olympusMasterEvent,
  olympusProposalEvent,
  olympusResultEvent,
  olympusUsageEvent,
  PROPOSAL_DIGEST,
} from "../helpers/olympus";

async function waitForProposalSubscription(page: Page) {
  await expect
    .poll(
      () =>
        page.evaluate(
          () =>
            window.__BUZZ_E2E_HAS_MOCK_GLOBAL_KIND_SUBSCRIPTION__?.(30192) ??
            false,
        ),
      { timeout: 15_000 },
    )
    .toBe(true);
}

async function emitOlympusEvent(page: Page, event: unknown) {
  await page.evaluate((value) => {
    window.__BUZZ_E2E_EMIT_MOCK_OLYMPUS_EVENT__?.(
      value as Parameters<
        NonNullable<typeof window.__BUZZ_E2E_EMIT_MOCK_OLYMPUS_EVENT__>
      >[0],
    );
  }, event);
}

async function requests(page: Page) {
  return page.evaluate(() => window.__BUZZ_E2E_OLYMPUS_REQUESTS__ ?? []);
}

async function waitForRequest(page: Page, count: number) {
  await expect.poll(async () => (await requests(page)).length).toBe(count);
  return (await requests(page))[count - 1];
}

test("the master DM shows the proposal card and reject sends a 44310", async ({
  page,
}) => {
  const proposal = olympusProposalEvent();
  await installMockBridge(page, {
    olympusEvents: [...olympusDevEvents(), olympusMasterEvent(), proposal],
  });
  await page.goto("/");
  const entry = page.getByTestId("master-agent-entry");
  await expect(entry).toContainText("mira", { timeout: 15_000 });
  await entry.getByRole("button").first().click();
  await expect(page.getByTestId("chat-title")).toHaveText("mira");

  const card = page
    .getByTestId("olympus-dm-proposals")
    .getByTestId("olympus-proposal-p-aada7279a890");
  await expect(card).toBeVisible({ timeout: 15_000 });
  await expect(card).toContainText("zeus/zeus proposes to patch Agent proof");
  await expect(card).toContainText("Workspace dev · namespace olympus-dev");
  await expect(card).toContainText(/Proposed 5m ago · expires in 23h/);
  await expect(card.getByTestId("olympus-proposal-reason")).toHaveText(
    "Proof is idle. **Suspend** it <b>now</b>.",
  );
  await expect(card.locator("b, strong")).toHaveCount(0);
  await expect(card.getByTestId("olympus-proposal-diff")).toHaveText(
    "spec.suspend-false→+true",
  );
  await expect(card.getByTestId("olympus-proposal-high-risk")).toHaveCount(0);

  await card.getByRole("button", { name: "Reject" }).click();
  const rejectDialog = page.getByTestId("olympus-reject-dialog");
  await expect(rejectDialog).toContainText("Reject this proposal?");
  await rejectDialog
    .getByTestId("olympus-reject-reason")
    .fill("  Keep proof running for the demo.  ");
  await expect(rejectDialog.getByTestId("olympus-reject-counter")).toHaveText(
    "32/1000",
  );
  await rejectDialog.getByRole("button", { name: "Reject proposal" }).click();
  await expect(rejectDialog).toBeHidden();
  await expect(
    card.getByTestId("olympus-proposal-request-p-aada7279a890"),
  ).toContainText("Reject: waiting for Hephaestus");
  await expect(card.getByRole("button", { name: "Approve" })).toBeDisabled();

  const request = await waitForRequest(page, 1);
  expect(request?.kind).toBe(44310);
  expect(request?.pubkey).toBe(OLYMPUS_OWNER);
  expect(request?.tags).toEqual([
    ["p", OLYMPUS_OPERATOR],
    ["workspace", "dev"],
    ["action", "reject"],
    ["proposal", "p-aada7279a890"],
  ]);
  expect(JSON.parse(request?.content ?? "")).toEqual({
    v: 1,
    action: "reject",
    workspace: "dev",
    proposal: "p-aada7279a890",
    digest: PROPOSAL_DIGEST,
    reason: "Keep proof running for the demo.",
  });

  await emitOlympusEvent(
    page,
    olympusResultEvent({
      requestId: request?.id ?? "",
      status: "accepted",
      reason: "rejected",
      action: "reject",
    }),
  );
  await expect(
    card.getByTestId("olympus-proposal-request-p-aada7279a890"),
  ).toContainText("Reject: accepted (rejected)");

  await waitForProposalSubscription(page);
  await emitOlympusEvent(
    page,
    olympusProposalEvent({
      phase: "rejected",
      result: {
        reason: "rejected",
        request: request?.id ?? "",
        at: Math.floor(Date.now() / 1000),
      },
      eventCreatedAt: Math.floor(Date.now() / 1000),
    }),
  );
  await expect(card).toHaveAttribute("data-phase", "rejected");
  await expect(card.getByRole("button", { name: "Approve" })).toHaveCount(0);
  await expect(card.getByRole("button", { name: "Reject" })).toHaveCount(0);
  await expect(card.getByTestId("olympus-proposal-result")).toContainText(
    "rejected",
  );

  await card
    .getByRole("button", { name: "Dismiss proposal p-aada7279a890" })
    .click();
  await expect(card).toHaveCount(0);
});

test("a high-risk approve needs the extra confirmation and sends highRisk", async ({
  page,
}) => {
  const highRisk = olympusProposalEvent({
    name: "p-0123456789ab",
    highRisk: ["secrets", "master agent"],
  });
  const expired = olympusProposalEvent({
    name: "p-expired00000",
    createdAt: Math.floor(Date.now() / 1000) - 90_000,
  });
  await installMockBridge(page, {
    olympusEvents: [...olympusDevEvents(), highRisk, expired],
  });
  await page.goto("/");
  await page.getByTestId("open-olympus-view").click();
  await page.getByTestId("olympus-tab-proposals").click();
  const list = page.getByTestId("olympus-proposals-panel");
  await expect(list).toBeVisible({ timeout: 10_000 });
  await expect(list.getByTestId("olympus-proposal-p-expired00000")).toHaveCount(
    0,
  );

  const card = list.getByTestId("olympus-proposal-p-0123456789ab");
  await expect(card.getByTestId("olympus-proposal-high-risk")).toBeVisible();
  await expect(card).toContainText("High risk: secrets, master agent");

  await card.getByRole("button", { name: "Approve" }).click();
  const dialog = page.getByRole("alertdialog");
  await expect(dialog).toContainText("Approve a high-risk change?");
  await expect(dialog).toContainText("High risk: secrets, master agent");
  await dialog.getByRole("button", { name: "Cancel" }).click();
  await expect(dialog).toBeHidden();
  expect(await requests(page)).toHaveLength(0);

  await card.getByRole("button", { name: "Approve" }).click();
  await page
    .getByRole("alertdialog")
    .getByRole("button", { name: "Approve high-risk change" })
    .click();

  const request = await waitForRequest(page, 1);
  expect(request?.tags).toEqual([
    ["p", OLYMPUS_OPERATOR],
    ["workspace", "dev"],
    ["action", "approve"],
    ["proposal", "p-0123456789ab"],
  ]);
  expect(JSON.parse(request?.content ?? "")).toEqual({
    v: 1,
    action: "approve",
    workspace: "dev",
    proposal: "p-0123456789ab",
    digest: PROPOSAL_DIGEST,
    highRisk: true,
  });

  await emitOlympusEvent(
    page,
    olympusResultEvent({
      requestId: request?.id ?? "",
      status: "refused",
      reason: "the target changed",
      action: "approve",
    }),
  );
  const status = card.getByTestId("olympus-proposal-request-p-0123456789ab");
  await expect(status).toContainText("Approve: refused. the target changed");

  await waitForProposalSubscription(page);
  await emitOlympusEvent(
    page,
    olympusProposalEvent({
      name: "p-0123456789ab",
      highRisk: ["secrets", "master agent"],
      phase: "failed",
      result: {
        reason: "the target changed",
        request: request?.id ?? "",
        at: Math.floor(Date.now() / 1000),
      },
      eventCreatedAt: Math.floor(Date.now() / 1000),
    }),
  );
  await expect(card).toHaveCount(0);
  await expect(list.getByTestId("olympus-proposals-empty")).toContainText(
    "Nothing waits for your decision",
  );
  await list.getByTestId("olympus-proposals-show-all").click();
  await expect(card).toHaveAttribute("data-phase", "failed");
  await expect(card.getByRole("button", { name: "Approve" })).toHaveCount(0);
  await expect(card.getByTestId("olympus-proposal-result")).toContainText(
    "the target changed",
  );
});

test("the master row counts its open proposals until they are decided", async ({
  page,
}) => {
  const now = Math.floor(Date.now() / 1000);
  await installMockBridge(page, {
    olympusEvents: [
      ...olympusDevEvents(),
      olympusMasterEvent(),
      olympusProposalEvent({ name: "p-000000000001" }),
      olympusProposalEvent({ name: "p-000000000002", createdAt: now - 60 }),
      olympusProposalEvent({
        name: "p-000000000003",
        requesterKey: "ab".repeat(32),
      }),
      olympusProposalEvent({
        name: "p-000000000004",
        createdAt: now - 90_000,
      }),
    ],
  });
  await page.goto("/");
  const entry = page.getByTestId("master-agent-entry");
  await expect(entry).toContainText("mira", { timeout: 15_000 });
  const pending = entry.getByTestId("master-agent-pending");
  await expect(pending).toHaveText("2 proposals wait for your approval");

  await waitForProposalSubscription(page);
  await emitOlympusEvent(
    page,
    olympusProposalEvent({
      name: "p-000000000001",
      phase: "applied",
      result: { reason: "applied", request: "f".repeat(64), at: now },
      eventCreatedAt: now,
    }),
  );
  await expect(pending).toHaveText("1 proposal waits for your approval");
  await emitOlympusEvent(
    page,
    olympusProposalEvent({
      name: "p-000000000002",
      createdAt: now - 60,
      phase: "rejected",
      result: { reason: "rejected", request: "e".repeat(64), at: now },
      eventCreatedAt: now + 1,
    }),
  );
  await expect(pending).toHaveCount(0);
});

test("a long value in the DM card shows a line diff with markers", async ({
  page,
}) => {
  const proposal = olympusProposalEvent({ name: "p-0000000000aa" });
  const content = JSON.parse(proposal.content);
  content.diff = [
    {
      path: "spec.instructions",
      from: JSON.stringify(
        "You are proof, the Olympus test agent.\nAnswer pings in the workspace channel.\nKeep answers short.",
      ),
      to: JSON.stringify(
        "You are proof, the Olympus test agent.\nAnswer pings and status questions in the workspace channel.\nKeep answers short.",
      ),
    },
  ];
  await installMockBridge(page, {
    olympusEvents: [
      ...olympusDevEvents(),
      olympusMasterEvent(),
      { ...proposal, content: JSON.stringify(content) },
    ],
  });
  await page.goto("/");
  const entry = page.getByTestId("master-agent-entry");
  await expect(entry).toContainText("mira", { timeout: 15_000 });
  await entry.getByRole("button").first().click();
  const card = page
    .getByTestId("olympus-dm-proposals")
    .getByTestId("olympus-proposal-p-0000000000aa");
  const lines = card
    .getByTestId("olympus-proposal-line-diff")
    .locator("[data-line]");
  await expect(lines).toHaveCount(4);
  await expect(lines.nth(0)).toHaveAttribute("data-line", "same");
  await expect(lines.nth(1)).toHaveAttribute("data-line", "del");
  await expect(lines.nth(1)).toContainText(
    "-removed: Answer pings in the workspace channel.",
  );
  await expect(lines.nth(2)).toHaveAttribute("data-line", "add");
  await expect(lines.nth(2)).toContainText(
    "+added: Answer pings and status questions in the workspace channel.",
  );
});

test("the Olympus page mounts the proposals and usage panels", async ({
  page,
}) => {
  const window24h = {
    tokens: { "claude-haiku-5-5": { input: 1_200, output: 300 } },
    turns: 2,
    apiErrors: 0,
    runs: 1,
    failedRuns: 0,
    share: 1,
  };
  await installMockBridge(page, {
    olympusEvents: [
      ...olympusDevEvents(),
      olympusProposalEvent(),
      olympusUsageEvent({
        workspace: "dev",
        name: "proof",
        windows: { "24h": window24h, "7d": window24h },
      }),
      olympusHecateEvent([
        {
          provider: "claude",
          credential: "primary",
          window: "five-hour",
          usedRatio: 0.4,
        },
      ]),
    ],
  });
  await page.goto("/");
  await page.getByTestId("open-olympus-view").click();
  await page.getByTestId("olympus-tab-proposals").click();
  await expect(page.getByTestId("olympus-proposals-panel")).toBeVisible({
    timeout: 15_000,
  });
  await expect(page.getByTestId("olympus-proposal-filters")).toBeVisible();
  await page.getByTestId("olympus-tab-usage").click();
  await expect(page.getByTestId("olympus-usage-row-dev-proof")).toBeVisible({
    timeout: 15_000,
  });
  await expect(page.getByTestId("olympus-usage-accounts")).toBeVisible();
});
