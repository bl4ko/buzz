import type { Page } from "@playwright/test";

export async function goToAgentsRoute(page: Page) {
  await page.evaluate(() => {
    window.location.hash = "#/agents";
  });
}
