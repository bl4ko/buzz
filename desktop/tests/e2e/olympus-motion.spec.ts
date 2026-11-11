import { expect, type Page, test } from "@playwright/test";

import { installMockBridge } from "../helpers/bridge";

function olympusAnimations(page: Page) {
  return page.evaluate(() =>
    [
      ...new Set(
        document
          .getAnimations()
          .filter((animation) => animation.playState === "running")
          .map((animation) =>
            animation instanceof CSSAnimation ? animation.animationName : "",
          )
          .filter((name) => name.startsWith("olympus-")),
      ),
    ].sort(),
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

test("welcome scene plays the intro, loops, and strikes", async ({ page }) => {
  await openWelcome(page);

  await expect
    .poll(() => olympusAnimations(page))
    .toEqual(
      expect.arrayContaining([
        "olympus-cross",
        "olympus-drift",
        "olympus-float",
        "olympus-glow",
        "olympus-halo",
        "olympus-hero-in",
        "olympus-letter-in",
        "olympus-spin",
        "olympus-twinkle",
      ]),
    );

  await expect(page.locator(".olympus-lockup")).toHaveAttribute(
    "data-strike",
    "i",
  );
  await expect
    .poll(() => olympusAnimations(page))
    .toEqual(
      expect.arrayContaining([
        "olympus-branch",
        "olympus-branch-draw",
        "olympus-flash",
        "olympus-punch",
      ]),
    );
  await expect(page.getByTestId("olympus-sky")).toHaveAttribute(
    "data-strike",
    "a",
    { timeout: 10_000 },
  );
});

for (const [width, height] of [
  [900, 600],
  [1280, 800],
  [1600, 1000],
]) {
  test(`ridges stay below the buttons at ${width}x${height}`, async ({
    page,
  }) => {
    await page.setViewportSize({ width, height });
    await openWelcome(page);

    const peak = await page
      .locator(".olympus-ridge--far polygon")
      .evaluate((ridge) => {
        for (const animation of document.getAnimations()) {
          if (animation.effect?.getComputedTiming().iterations !== Infinity) {
            animation.finish();
          }
        }
        return ridge.getBoundingClientRect().top;
      });
    const button = await page
      .getByRole("button", { name: "Use an existing key" })
      .boundingBox();

    expect(peak).toBeLessThan(height);
    expect(peak).toBeGreaterThanOrEqual(
      (button?.y ?? height) + (button?.height ?? 0) + 16,
    );
  });
}

test("launch frame holds the medallion at the window centre", async ({
  page,
}) => {
  await openWelcome(page);

  const offset = await page.locator(".olympus-hero__art").evaluate((art) => {
    const intro = art
      .getAnimations()
      .find(
        (animation) =>
          animation instanceof CSSAnimation &&
          animation.animationName === "olympus-hero-in",
      );
    if (!intro) return null;
    intro.pause();
    intro.currentTime = 0;
    const { height, top } = art.getBoundingClientRect();
    return top + height / 2 - window.innerHeight / 2;
  });

  expect(offset).not.toBeNull();
  expect(Math.abs(offset ?? 0)).toBeLessThanOrEqual(1);
});

test("returning to the welcome page skips the intro", async ({ page }) => {
  await openWelcome(page);
  await page.getByRole("button", { name: "Create a new identity key" }).click();
  await page.getByTestId("onboarding-back").click();
  await expect(page.getByTestId("olympus-hero")).toBeVisible();

  const animations = await olympusAnimations(page);
  expect(animations).toContain("olympus-float");
  expect(animations).not.toContain("olympus-hero-in");
  expect(animations).not.toContain("olympus-letter-in");
  expect(animations).not.toContain("olympus-fade-up");
});

test("reduced motion stills the welcome scene and spinners", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await openWelcome(page);

  await expect.poll(() => olympusAnimations(page)).toEqual(["olympus-pulse"]);
  await page.waitForTimeout(1_200);
  await expect(page.locator(".olympus-lockup")).not.toHaveAttribute(
    "data-strike",
  );

  await page.evaluate(() => {
    const host = document.createElement("div");
    host.innerHTML =
      '<span class="olympus-bolt"><svg class="olympus-bolt__comet"></svg><span class="olympus-bolt__punch"></span></span>' +
      '<span class="olympus-puffs"><svg class="olympus-inline"><polygon></polygon></svg></span>';
    document.body.append(host);
  });
  expect(await olympusAnimations(page)).toEqual([
    "olympus-pulse",
    "olympus-pulse-inline",
  ]);
  await expect(page.locator(".olympus-bolt__comet")).toHaveCSS(
    "display",
    "none",
  );
  await expect(page.locator(".olympus-inline polygon")).toHaveCSS(
    "opacity",
    "1",
  );
});
