import { expect, type Page, test } from "@playwright/test";

import { installMockBridge } from "../helpers/bridge";

function olympusAnimations(page: Page) {
  return page.evaluate(() =>
    document
      .getAnimations()
      .map((animation) =>
        animation instanceof CSSAnimation ? animation.animationName : "",
      )
      .filter((name) => name.startsWith("olympus-"))
      .sort(),
  );
}

async function openWelcome(page: Page) {
  await installMockBridge(page, undefined, {
    skipCommunitySeed: true,
    skipOnboardingSeed: true,
  });
  await page.goto("/");
  await expect(page.getByTestId("olympus-hero")).toBeVisible();
}

test("welcome scene drifts clouds and strikes the bolt", async ({ page }) => {
  await openWelcome(page);

  await expect
    .poll(() => olympusAnimations(page))
    .toEqual(
      expect.arrayContaining([
        "olympus-drift",
        "olympus-drift-front",
        "olympus-flash",
        "olympus-strike",
      ]),
    );
});

test("reduced motion stills the welcome scene and spinners", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await openWelcome(page);

  expect(await olympusAnimations(page)).toEqual([]);
  await expect(page.locator(".olympus-hero__bolt")).toHaveCSS("opacity", "1");

  await page.evaluate(() => {
    const host = document.createElement("div");
    host.innerHTML =
      '<span class="olympus-bolt"><span class="olympus-bolt__clip"><span class="olympus-bolt__fill"></span></span></span>' +
      '<span class="olympus-puffs"><span class="olympus-puff"></span><span class="olympus-puff"></span><span class="olympus-puff"></span></span>';
    document.body.append(host);
  });
  expect(await olympusAnimations(page)).toEqual([]);
  await expect(page.locator(".olympus-bolt__fill")).toHaveCSS(
    "transform",
    "none",
  );
  await expect(page.locator(".olympus-puff").first()).toHaveCSS("opacity", "1");
});
