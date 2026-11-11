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

test("welcome scene plays the intro, loops, and lightning", async ({
  page,
}) => {
  await openWelcome(page);

  await expect
    .poll(() => olympusAnimations(page))
    .toEqual(
      expect.arrayContaining([
        "olympus-cloud-back",
        "olympus-cloud-front",
        "olympus-cloud-mid",
        "olympus-drift-back",
        "olympus-drift-front",
        "olympus-drift-ridge",
        "olympus-halo",
        "olympus-letter-in",
        "olympus-rise-in",
        "olympus-seal-in",
        "olympus-spin",
        "olympus-twinkle",
        "olympus-twinkle-disc",
        "olympus-wisp",
      ]),
    );

  for (const names of [
    ["olympus-draw", "olympus-flash", "olympus-strike"],
    ["olympus-sheet"],
    ["olympus-flicker"],
  ]) {
    await expect
      .poll(() => olympusAnimations(page), {
        intervals: [50],
        timeout: 10_000,
      })
      .toEqual(expect.arrayContaining(names));
  }
});

test("launch frame holds the seal at the window centre", async ({ page }) => {
  await openWelcome(page);

  const offset = await page.locator(".olympus-seal").evaluate((seal) => {
    const intro = seal
      .getAnimations()
      .find(
        (animation) =>
          animation instanceof CSSAnimation &&
          animation.animationName === "olympus-seal-in",
      );
    if (!intro) return null;
    intro.pause();
    intro.currentTime = 0;
    const { height, top } = seal.getBoundingClientRect();
    return top + height / 2 - window.innerHeight / 2;
  });

  expect(offset).not.toBeNull();
  expect(Math.abs(offset ?? 0)).toBeLessThanOrEqual(1);
});

for (const [width, height] of [
  [900, 650],
  [1280, 800],
  [1600, 1000],
]) {
  test(`text and buttons stay clear of the clouds at ${width}x${height}`, async ({
    page,
  }) => {
    await page.setViewportSize({ width, height });
    await openWelcome(page);

    await page.evaluate(() => {
      for (const animation of document.getAnimations()) {
        if (animation.effect?.getComputedTiming().iterations !== Infinity) {
          animation.finish();
        }
      }
    });
    const ground = await page.locator(".olympus-sky__ground").boundingBox();
    const footer = await page
      .getByTestId("onboarding-footer-slot")
      .boundingBox();
    const button = await page
      .getByRole("button", { name: "Use an existing key" })
      .boundingBox();
    const bottom = (button?.y ?? height) + (button?.height ?? 0);

    expect(bottom).toBeLessThanOrEqual(footer?.y ?? 0);
    expect(bottom).toBeLessThanOrEqual(
      (ground?.y ?? 0) + ((ground?.height ?? 0) * 800) / 900 + 0.5,
    );
  });
}

test("returning to the welcome page skips the intro", async ({ page }) => {
  await openWelcome(page);
  await page.getByRole("button", { name: "Create a new identity key" }).click();
  await page.getByTestId("onboarding-back").click();
  await expect(page.getByTestId("olympus-hero")).toBeVisible();

  const animations = await olympusAnimations(page);
  expect(animations).toContain("olympus-halo");
  expect(animations).not.toContain("olympus-seal-in");
  expect(animations).not.toContain("olympus-letter-in");
  expect(animations).not.toContain("olympus-fade-up");
});

test("reduced motion stills the welcome scene and loaders", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await openWelcome(page);

  await expect
    .poll(() => olympusAnimations(page))
    .toEqual(["olympus-halo-calm"]);
  await expect(page.locator(".olympus-strike").first()).toBeHidden();

  await page.evaluate(() => {
    const host = document.createElement("div");
    host.innerHTML =
      '<span class="olympus-bolt"><svg><path class="olympus-bolt__tile"></path></svg></span>' +
      '<span class="olympus-puffs"><svg class="olympus-inline olympus-inline--16"><path class="olympus-inline__tile"></path></svg></span>';
    document.body.append(host);
  });
  expect(await olympusAnimations(page)).toEqual([
    "olympus-halo-calm",
    "olympus-pulse",
    "olympus-pulse-inline",
  ]);
  await expect(page.locator(".olympus-bolt__tile")).toHaveCSS("opacity", "1");
  await expect(page.locator(".olympus-inline__tile")).toHaveCSS("opacity", "1");
});
