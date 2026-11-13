import { expect, type Page, test } from "@playwright/test";

import { installMockBridge } from "../helpers/bridge";
import {
  MASTER_PUBLIC_KEY,
  olympusDevEvents,
  olympusMasterEvent,
} from "../helpers/olympus";

const GENERAL_ROOT_ID = "c".repeat(64);

async function openGeneral(page: Page, withMaster: boolean) {
  await installMockBridge(page, {
    olympusEvents: withMaster
      ? [...olympusDevEvents(), olympusMasterEvent()]
      : olympusDevEvents(),
  });
  await page.goto("/");
  await page.getByTestId("channel-general").click();
  await expect(page.getByTestId("chat-title")).toHaveText("general");
}

async function emitMessage(page: Page, content: string) {
  await expect
    .poll(() =>
      page.evaluate(
        () => typeof window.__BUZZ_E2E_EMIT_MOCK_MESSAGE__ === "function",
      ),
    )
    .toBe(true);
  await page.evaluate(
    ({ content, id }) => {
      const emit = window.__BUZZ_E2E_EMIT_MOCK_MESSAGE__;
      if (!emit) throw new Error("Mock message emitter is unavailable.");
      emit({ channelName: "general", content, id });
    },
    { content, id: GENERAL_ROOT_ID },
  );
  const row = page.locator(`[data-message-id="${GENERAL_ROOT_ID}"]`);
  await expect(row).toContainText(content);
  return row;
}

test("no master agent hides every entry point", async ({ page }) => {
  await openGeneral(page, false);
  await emitMessage(page, "Backup failed at 03:00");
  await expect(page.getByTestId("master-agent-entry")).toHaveCount(0);

  await page.keyboard.press("ControlOrMeta+j");
  await expect(page.getByTestId("chat-title")).toHaveText("general");

  await page.keyboard.press("ControlOrMeta+k");
  await expect(
    page.getByTestId("search-result-action-browse-channels"),
  ).toBeVisible();
  await expect(page.getByTestId("search-result-action-ask-master")).toHaveCount(
    0,
  );
  await page.keyboard.press("Escape");

  const row = page.locator(`[data-message-id="${GENERAL_ROOT_ID}"]`);
  await row.hover();
  await row.getByTestId(`more-actions-${GENERAL_ROOT_ID}`).click();
  await expect(
    page.getByTestId(`copy-message-link-${GENERAL_ROOT_ID}`),
  ).toBeVisible();
  await expect(page.getByTestId(`ask-master-${GENERAL_ROOT_ID}`)).toHaveCount(
    0,
  );
});

test("the pinned entry opens the master DM by its profile name", async ({
  page,
}) => {
  await openGeneral(page, true);
  const entry = page.getByTestId("master-agent-entry");
  await expect(entry).toContainText("mira", { timeout: 15_000 });
  await expect(entry).not.toContainText("Spec name");
  await entry.getByRole("button").first().click();
  await expect(page.getByTestId("chat-title")).toHaveText("mira");
  await expect(page.getByTestId("dm-list")).not.toContainText("mira");
});

test("⌘J quotes the selected message text into the master DM draft", async ({
  page,
}) => {
  await openGeneral(page, true);
  await expect(page.getByTestId("master-agent-entry")).toContainText("mira", {
    timeout: 15_000,
  });
  const row = await emitMessage(page, "Backup failed at 03:00");
  await row.getByText("Backup failed at 03:00").selectText();
  await page.keyboard.press("ControlOrMeta+j");

  await expect(page.getByTestId("chat-title")).toHaveText("mira");
  const input = page.getByTestId("message-input");
  await expect(input.locator("blockquote")).toHaveText(
    "Backup failed at 03:00",
  );
  await expect(input.locator("[data-composer-buzz-link]")).toHaveCount(1);
});

test("⌘J quotes the composer text when nothing is selected", async ({
  page,
}) => {
  await openGeneral(page, true);
  await expect(page.getByTestId("master-agent-entry")).toContainText("mira", {
    timeout: 15_000,
  });
  const general = page.getByTestId("message-input");
  await general.click();
  await general.fill("is this right?");
  await page.keyboard.press("ControlOrMeta+j");

  await expect(page.getByTestId("chat-title")).toHaveText("mira");
  const input = page.getByTestId("message-input");
  await expect(input.locator("blockquote")).toHaveText("is this right?");
  await expect(input).toBeFocused();
  await page.keyboard.type("Why?");
  await expect(input.locator("blockquote")).toHaveText("is this right?");
  await expect(input.locator(":scope > p").last()).toContainText("Why?");
});

test("message menu and palette ask the master without sending", async ({
  page,
}) => {
  await openGeneral(page, true);
  await expect(page.getByTestId("master-agent-entry")).toContainText("mira", {
    timeout: 15_000,
  });
  const row = await emitMessage(page, "Disk is at 91 percent");
  await row.hover();
  await row.getByTestId(`more-actions-${GENERAL_ROOT_ID}`).click();
  const ask = page.getByTestId(`ask-master-${GENERAL_ROOT_ID}`);
  await expect(ask).toHaveText("Ask mira");
  await ask.click();

  await expect(page.getByTestId("chat-title")).toHaveText("mira");
  const input = page.getByTestId("message-input");
  await expect(input.locator("blockquote")).toHaveText("Disk is at 91 percent");
  await expect(input.locator("[data-composer-buzz-link]")).toHaveCount(1);
  await expect(
    page.locator("[data-message-id]").filter({ hasText: "91 percent" }),
  ).toHaveCount(0);

  await page.getByTestId("channel-general").click();
  await expect(page.getByTestId("chat-title")).toHaveText("general");
  await page.keyboard.press("ControlOrMeta+k");
  const action = page.getByTestId("search-result-action-ask-master");
  await expect(action).toContainText("Ask mira");
  await action.click();
  await expect(page.getByTestId("chat-title")).toHaveText("mira");
});

test("the master agent's typing shows as agent work in its DM", async ({
  page,
}) => {
  await openGeneral(page, true);
  const entry = page.getByTestId("master-agent-entry");
  await expect(entry).toContainText("mira", { timeout: 15_000 });
  await entry.getByRole("button").first().click();
  await expect(page.getByTestId("chat-title")).toHaveText("mira");
  await expect(page).toHaveURL(/\/channels\/[^/?#]+/);
  const channelId = decodeURIComponent(
    new URL(page.url()).pathname.split("/")[2] ?? "",
  );

  const trigger = page.getByTestId("bot-activity-composer-trigger");
  await expect(async () => {
    await page.evaluate(
      ({ channelId, pubkey }) => {
        window.__BUZZ_E2E_EMIT_MOCK_TYPING__?.({
          channelId,
          channelName: "",
          pubkey,
        });
      },
      { channelId, pubkey: MASTER_PUBLIC_KEY },
    );
    await expect(trigger).toBeVisible({ timeout: 1_000 });
  }).toPass({ timeout: 15_000 });
  await expect(page.getByTestId("message-typing-indicator")).toHaveCount(0);

  await trigger.click();
  const item = page.getByTestId(
    `bot-activity-composer-item-${MASTER_PUBLIC_KEY}`,
  );
  await expect(item).toContainText("View activity");
  await item.click({ force: true });
  await expect(page.getByTestId("agent-session-thread-panel")).toContainText(
    "mira",
  );
});
