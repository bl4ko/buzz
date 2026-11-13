import { expect, type Page, test } from "@playwright/test";

import { installMockBridge } from "../helpers/bridge";
import {
  OLYMPUS_OPERATOR,
  OLYMPUS_OWNER,
  olympusDevEvents,
  olympusMasterEvent,
  olympusProposalEvent,
  olympusResultEvent,
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
    "spec.suspend: false → true",
  );
  await expect(card.getByTestId("olympus-proposal-high-risk")).toHaveCount(0);

  await card.getByRole("button", { name: "Reject" }).click();
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
  await expect(card).toContainText("Result: rejected");

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
  await page.getByTestId("open-agents-view").click();
  const list = page.getByTestId("olympus-proposals");
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
  await expect(card).toHaveAttribute("data-phase", "failed");
  await expect(card.getByRole("button", { name: "Approve" })).toHaveCount(0);
  await expect(card).toContainText("Result: the target changed");
});
