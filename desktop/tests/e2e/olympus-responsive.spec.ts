import { expect, type Page, test } from "@playwright/test";

import { waitForAnimations } from "../helpers/animations";
import { installMockBridge } from "../helpers/bridge";
import { olympusDevEvents, olympusUsageEvent } from "../helpers/olympus";
import { olympusOpsEvents } from "../helpers/olympusPage";

const SHOT_DIR =
  process.env.OLYMPUS_SHOT_DIR ?? "test-results/olympus-responsive";

const usageWindow = (scale: number) => ({
  tokens: {
    "claude-opus-5-5": {
      input: 120_000 * scale,
      output: 30_000 * scale,
      cacheRead: 2_400_000 * scale,
    },
    "gpt-5.5-codex": { input: 40_000 * scale, output: 9_000 * scale },
  },
  turns: 14 * scale,
  apiErrors: 0,
  runs: 3 * scale,
  failedRuns: scale > 1 ? 1 : 0,
  share: 0.5,
});

function usageEvents() {
  const now = Math.floor(Date.now() / 1000);
  return ["argus", "zeus"].map((name, index) =>
    olympusUsageEvent({
      workspace: "ops",
      name,
      windows: { "24h": usageWindow(index + 1), "7d": usageWindow(index + 3) },
      lastRun: { schedule: "daily-report", at: now - 3_600, result: "failed" },
    }),
  );
}

async function openOlympus(
  page: Page,
  width: number,
  scheme: "light" | "dark",
) {
  await page.setViewportSize({ width, height: 700 });
  await page.emulateMedia({ colorScheme: scheme });
  await installMockBridge(page, {
    olympusEvents: [
      ...olympusDevEvents(),
      ...olympusOpsEvents(),
      ...usageEvents(),
    ],
  });
  await page.goto("/");
  await page.getByTestId("open-olympus-view").click();
  await expect(page.getByTestId("olympus-page")).toBeVisible({
    timeout: 10_000,
  });
}

function overlap(
  a: { x: number; y: number; width: number; height: number },
  b: { x: number; y: number; width: number; height: number },
) {
  return (
    a.x < b.x + b.width &&
    b.x < a.x + a.width &&
    a.y < b.y + b.height &&
    b.y < a.y + a.height
  );
}

for (const scheme of ["light", "dark"] as const) {
  for (const width of [900, 1440]) {
    test(`agents and usage fit at ${width}px (${scheme})`, async ({ page }) => {
      await openOlympus(page, width, scheme);

      const zeus = page.getByTestId("olympus-agent-row-zeus");
      await expect(zeus).toBeVisible({ timeout: 15_000 });
      const name = zeus.getByTestId("olympus-agent-label");
      const badge = zeus.getByTestId("olympus-master-chip");
      await expect(name).toHaveText("Zeus");
      await expect(badge).toBeVisible();
      const nameBox = await name.boundingBox();
      const badgeBox = await badge.boundingBox();
      if (!nameBox || !badgeBox) throw new Error("Zeus row is not laid out");
      expect(overlap(nameBox, badgeBox)).toBe(false);
      expect(
        await name.evaluate((node) => node.scrollWidth <= node.clientWidth),
      ).toBe(true);
      const rowBox = await zeus.boundingBox();
      expect(badgeBox.x + badgeBox.width).toBeLessThanOrEqual(
        (rowBox?.x ?? 0) + (rowBox?.width ?? 0),
      );
      await page.screenshot({
        path: `${SHOT_DIR}/agents-${width}-${scheme}.png`,
      });

      await page.getByTestId("olympus-tab-usage").click();
      const table = page.getByTestId("olympus-usage-table");
      await expect(page.getByTestId("olympus-usage-row-ops-zeus")).toBeVisible({
        timeout: 15_000,
      });
      const fit = await table.evaluate((node) => {
        const frame = node.parentElement as HTMLElement;
        const scroller = node.closest(".overflow-y-auto") as HTMLElement;
        return {
          frame: frame.scrollWidth <= frame.clientWidth,
          page: scroller.scrollWidth <= scroller.clientWidth,
          table: node.getBoundingClientRect().width <= frame.clientWidth + 0.5,
        };
      });
      expect(fit).toEqual({ frame: true, page: true, table: true });
      await expect(
        page.getByTestId("olympus-usage-row-ops-zeus"),
      ).toContainText("Zeus");
      await expect(
        page.getByTestId("olympus-usage-row-ops-zeus"),
      ).toContainText("failed");
      await page.screenshot({
        path: `${SHOT_DIR}/usage-${width}-${scheme}.png`,
      });
    });
  }
}

test("onboarding steps use the Olympus colors", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await installMockBridge(page, undefined, {
    skipCommunitySeed: true,
    skipOnboardingSeed: true,
  });
  await page.goto("/");
  await expect(page.getByTestId("machine-onboarding-gate")).toBeVisible();
  await page.getByRole("button", { name: "Use an existing key" }).click();
  await expect(
    page.getByRole("heading", { name: "Enter your private key" }),
  ).toBeVisible();
  await waitForAnimations(page);

  const shell = page.locator(".buzz-startup-shell").first();
  const look = await shell.evaluate((node) => {
    const style = window.getComputedStyle(node);
    return {
      image: style.backgroundImage,
      top: style.getPropertyValue("--buzz-welcome-chartreuse").trim(),
      bottom: style.getPropertyValue("--buzz-onboarding-shell-bottom").trim(),
    };
  });
  expect(look.top.toLowerCase()).toBe("#f5ebd0");
  expect(look.image).toContain("rgb(245, 235, 208)");
  expect(look.image).not.toContain("rgb(215, 215, 46)");
  expect(look.image).not.toContain("rgb(215, 231, 246)");
  await page.screenshot({ path: `${SHOT_DIR}/onboarding-import.png` });

  await page.getByTestId("onboarding-back").click();
  await page.getByRole("button", { name: "Create a new identity key" }).click();
  await expect(page.getByTestId("onboarding-key-guidance")).toBeVisible();
  await waitForAnimations(page);
  await page.screenshot({ path: `${SHOT_DIR}/onboarding-create.png` });
});
