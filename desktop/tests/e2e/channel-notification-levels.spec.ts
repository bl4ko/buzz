import { expect, type Page, test } from "@playwright/test";

import { installMockBridge } from "../helpers/bridge";
import { openSettings } from "../helpers/settings";

const MOCK_PUBKEY = "deadbeef".repeat(8);
const BOT_PUBKEY = "b0".repeat(32);
const ENGINEERING_CHANNEL_ID = "1c7e1c02-87bb-5e88-b2da-5a7a9432d0c9";
const RANDOM_CHANNEL_ID = "9dae0116-799b-5071-a0a8-fdd30a91a35d";
const MUTE_STORAGE_KEY = `buzz-channel-mutes.v1:${MOCK_PUBKEY}`;
const SCREENSHOT_DIR = process.env.WPC_SCREENSHOT_DIR;

function relayEvent(
  kind: number,
  pubkey: string,
  tags: string[][],
  content = "",
) {
  return {
    id: `${kind}`.padStart(64, "0"),
    pubkey,
    created_at: 1_700_000_000,
    kind,
    tags,
    content,
    sig: "0".repeat(128),
  };
}

const AGENT_CHANNEL_EVENTS = [
  relayEvent(39002, "ab".repeat(32), [
    ["d", ENGINEERING_CHANNEL_ID],
    ["p", MOCK_PUBKEY, "", "owner"],
    ["p", BOT_PUBKEY, "", "member"],
  ]),
  relayEvent(0, BOT_PUBKEY, [], JSON.stringify({ name: "zeus", bot: true })),
];

async function storedEntry(page: Page, channelId: string) {
  return page.evaluate(
    ({ key, id }) =>
      JSON.parse(window.localStorage.getItem(key) ?? "{}").channels?.[id] ??
      null,
    { key: MUTE_STORAGE_KEY, id: channelId },
  );
}

async function shot(page: Page, name: string) {
  if (SCREENSHOT_DIR) {
    await page.waitForTimeout(500);
    await page.screenshot({ path: `${SCREENSHOT_DIR}/${name}.png` });
  }
}

test.describe("channel notification levels", () => {
  test("context menu sets a level and shows the agent default", async ({
    page,
  }) => {
    await installMockBridge(page, { extraRelayEvents: AGENT_CHANNEL_EVENTS });
    await page.goto("/");
    await page.getByTestId("channel-general").click();
    await expect(page.getByTestId("chat-title")).toHaveText("general");

    await page.getByTestId("channel-engineering").click({ button: "right" });
    await page.getByTestId("channel-notification-level-menu").click();
    await expect(
      page.getByTestId("channel-notification-level-default"),
    ).toHaveText("Default (Mentions and DMs)");
    await shot(page, "levels-context-menu-agent-channel");
    await page.keyboard.press("Escape");
    await page.keyboard.press("Escape");
    await expect(
      page.getByTestId("channel-notification-level-menu"),
    ).toHaveCount(0);

    await page.getByTestId("channel-random").click({ button: "right" });
    await page.getByTestId("channel-notification-level-menu").click();
    await expect(
      page.getByTestId("channel-notification-level-default"),
    ).toHaveText("Default (All new messages)");
    await page.getByTestId("channel-notification-level-mentions").click();
    await expect
      .poll(() => storedEntry(page, RANDOM_CHANNEL_ID))
      .toMatchObject({ muted: false, level: "mentions" });

    await page.getByTestId("channel-random").click({ button: "right" });
    await page.getByTestId("channel-notification-level-menu").click();
    await page.getByTestId("channel-notification-level-nothing").click();
    await expect
      .poll(() => storedEntry(page, RANDOM_CHANNEL_ID))
      .toMatchObject({ muted: true, level: "nothing" });
    await expect(
      page.getByTestId("channel-random").locator("svg.lucide-bell-off"),
    ).toHaveCount(1);

    await page.getByTestId("channel-random").click({ button: "right" });
    await page.getByTestId("channel-notification-level-menu").click();
    await page.getByTestId("channel-notification-level-default").click();
    await expect
      .poll(() => storedEntry(page, RANDOM_CHANNEL_ID))
      .toEqual({ muted: false, updatedAt: expect.any(Number) });
  });

  test("settings lists channels with their level", async ({ page }) => {
    await installMockBridge(page, { extraRelayEvents: AGENT_CHANNEL_EVENTS });
    await page.goto("/");
    await openSettings(page, "notifications");

    const card = page.getByTestId("settings-channel-notification-levels");
    await expect(card).toBeVisible();
    const engineering = page.getByTestId(
      `channel-notification-level-row-${ENGINEERING_CHANNEL_ID}`,
    );
    await expect(engineering).toContainText(
      "Default for a channel with agents: Mentions and DMs",
    );
    const random = page.getByTestId(
      `channel-notification-level-row-${RANDOM_CHANNEL_ID}`,
    );
    await expect(random).toContainText("Default: All new messages");

    await random
      .getByTestId(`channel-notification-level-${RANDOM_CHANNEL_ID}-nothing`)
      .click();
    await expect(random).toContainText(
      "Set by you. Default: All new messages.",
    );
    await expect
      .poll(() => storedEntry(page, RANDOM_CHANNEL_ID))
      .toMatchObject({ muted: true, level: "nothing" });
    await card.scrollIntoViewIfNeeded();
    await shot(page, "levels-settings-card");

    await random
      .getByTestId(`channel-notification-level-reset-${RANDOM_CHANNEL_ID}`)
      .click();
    await expect(random).toContainText("Default: All new messages");
  });
});
