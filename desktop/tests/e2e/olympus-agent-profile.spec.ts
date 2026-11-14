import { expect, type Page, test } from "@playwright/test";

import { waitForAnimations } from "../helpers/animations";
import { installMockBridge } from "../helpers/bridge";
import {
  OLYMPUS_OWNER,
  olympusDevEvents,
  olympusUsageEvent,
} from "../helpers/olympus";
import {
  ARGUS_PUBLIC_KEY,
  olympusArgusEvent,
  olympusOpsEvents,
  olympusOpsResult,
} from "../helpers/olympusPage";

const SHOTS = "test-results/olympus-agent-profile";
const STRANGER = "5a1e0000".repeat(8);

function appArgus(owner = OLYMPUS_OWNER) {
  const event = olympusArgusEvent();
  const content = JSON.parse(event.content);
  content.owner = owner;
  content.managedBy = null;
  content.gitopsFields = [];
  content.spec.respondTo = [STRANGER];
  content.status.conditions.push({
    type: "BackupReady",
    status: "False",
    reason: "BackupFailed",
    message: "restic: repository is locked by another process",
    lastTransitionTime: new Date(Date.now() - 600_000).toISOString(),
  });
  return {
    ...event,
    created_at: event.created_at + 5,
    content: JSON.stringify(content),
  };
}

function usage() {
  const window = (scale: number) => ({
    tokens: {
      "claude-opus-5-5": {
        input: 120_000 * scale,
        output: 30_000 * scale,
        cacheRead: 2_400_000 * scale,
      },
    },
    turns: 14 * scale,
    apiErrors: 0,
    runs: 3 * scale,
    failedRuns: 1,
    share: 0.5,
  });
  return olympusUsageEvent({
    workspace: "ops",
    name: "argus",
    windows: { "24h": window(1), "7d": window(4) },
    lastRun: {
      schedule: "daily-os-updates",
      at: Math.floor(Date.now() / 1000) - 3_600,
      result: "failed",
    },
  });
}

async function openProfile(
  page: Page,
  argus = appArgus(),
  scheme: "light" | "dark" = "light",
) {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.emulateMedia({ colorScheme: scheme });
  await installMockBridge(page, {
    olympusEvents: [
      ...olympusDevEvents(),
      ...olympusOpsEvents(),
      argus,
      usage(),
    ],
    searchProfiles: [
      {
        pubkey: ARGUS_PUBLIC_KEY,
        displayName: "Argus",
        about: "Observability",
        ownerPubkey: OLYMPUS_OWNER,
        isAgent: true,
      },
    ],
  });
  await page.goto(`/#/agents?profile=${ARGUS_PUBLIC_KEY}`);
  const panel = page.getByTestId("user-profile-panel");
  await expect(panel).toBeVisible({ timeout: 10_000 });
  return panel;
}

async function waitForRequest(page: Page, count: number) {
  await expect
    .poll(() =>
      page.evaluate(() => window.__BUZZ_E2E_OLYMPUS_REQUESTS__?.length ?? 0),
    )
    .toBe(count);
  return page.evaluate(
    (index) => window.__BUZZ_E2E_OLYMPUS_REQUESTS__?.[index],
    count - 1,
  );
}

async function choose(page: Page, label: string, option: string) {
  await page.getByRole("button", { name: new RegExp(`^${label}:`) }).click();
  await page.getByRole("menuitemradio", { name: option }).click();
}

for (const scheme of ["light", "dark"] as const) {
  test(`the owner sees the Olympus properties in the profile (${scheme})`, async ({
    page,
  }) => {
    const panel = await openProfile(page, appArgus(), scheme);
    const section = panel.getByTestId("olympus-profile");
    await expect(section).toBeVisible({ timeout: 10_000 });
    await expect(section.getByTestId("olympus-profile-status")).toContainText(
      "Online",
    );
    await expect(section.getByTestId("olympus-profile-status")).toContainText(
      "Active 3 min ago",
    );
    await expect(section.getByTestId("olympus-profile-error")).toContainText(
      "BackupFailed",
    );
    await expect(section.getByTestId("olympus-profile-error")).toContainText(
      "repository is locked",
    );
    await expect(
      section.getByTestId("olympus-profile-workspace"),
    ).toContainText("ops");
    await expect(
      section.getByRole("button", { name: /^Model:/ }),
    ).toBeVisible();
    await expect(
      section.getByRole("button", { name: /^Effort:/ }),
    ).toBeVisible();
    await expect(section).toContainText("claude-code");
    await expect(section).toContainText("Responds to");
    await expect(section).toContainText("Bank workspace");
    await expect(
      section.getByTestId("olympus-profile-instructions"),
    ).toContainText("agents/argus/agents/argus.md");
    await expect(
      section.getByTestId("olympus-profile-schedule-daily-os-updates"),
    ).toContainText("Failed");
    await expect(
      section.getByTestId("olympus-profile-schedule-argus-report"),
    ).toContainText("Succeeded");
    await expect(section.getByTestId("olympus-agent-usage")).toBeVisible();
    await expect(panel.getByTestId("user-profile-info-sections")).toBeVisible();
    await waitForAnimations(page);
    await panel.screenshot({ path: `${SHOTS}/01-profile-${scheme}.png` });
    await page
      .getByTestId("user-profile-scroll-body")
      .evaluate((node) => node.scrollTo(0, node.scrollHeight));
    await waitForAnimations(page);
    await panel.screenshot({ path: `${SHOTS}/02-profile-end-${scheme}.png` });
  });
}

test("quick edits send a patch for model and effort", async ({ page }) => {
  const panel = await openProfile(page);
  const section = panel.getByTestId("olympus-profile");
  await expect(section).toBeVisible({ timeout: 10_000 });
  await choose(page, "Model", "claude-sonnet-5-5");
  const model = await waitForRequest(page, 1);
  const modelContent = JSON.parse(model?.content ?? "");
  expect(modelContent).toMatchObject({
    v: 1,
    action: "patch",
    workspace: "ops",
    agent: "argus",
    patch: { model: "claude-sonnet-5-5" },
  });
  expect(Object.keys(modelContent.patch)).toEqual(["model"]);
  await page.evaluate(
    (value) => {
      window.__BUZZ_E2E_EMIT_MOCK_OLYMPUS_EVENT__?.(
        value as Parameters<
          NonNullable<typeof window.__BUZZ_E2E_EMIT_MOCK_OLYMPUS_EVENT__>
        >[0],
      );
    },
    olympusOpsResult({
      requestId: model?.id ?? "",
      status: "accepted",
      reason: "applied",
      action: "patch",
      agent: "argus",
    }),
  );
  await expect(section.getByTestId("olympus-profile-request")).toContainText(
    "accepted",
  );

  await choose(page, "Effort", "Default");
  const effort = await waitForRequest(page, 2);
  expect(JSON.parse(effort?.content ?? "").patch).toEqual({ effort: null });
  await waitForAnimations(page);
  await panel.screenshot({ path: `${SHOTS}/03-quick-edit.png` });
});

test("Edit opens the Olympus editor drawer", async ({ page }) => {
  const panel = await openProfile(page);
  await panel.getByTestId("olympus-profile-edit").click();
  const editor = page.getByTestId("olympus-agent-editor");
  await expect(editor).toBeVisible();
  await expect(editor).toContainText("Edit argus");
  await waitForAnimations(page);
  await page.screenshot({ path: `${SHOTS}/04-editor.png` });
});

test("an agent of another owner keeps the plain profile", async ({ page }) => {
  const panel = await openProfile(page, appArgus(STRANGER));
  await expect(panel.getByTestId("user-profile-info-sections")).toBeVisible();
  await expect(panel.getByTestId("olympus-profile")).toHaveCount(0);
});
