import { expect, type Page, test } from "@playwright/test";

import { installMockBridge, TEST_IDENTITIES } from "../helpers/bridge";
import { olympusDevEvents, olympusProposalEvent } from "../helpers/olympus";
import { olympusOpsEvents } from "../helpers/olympusPage";

const SHOTS = "test-results/olympus-owner-feedback";

async function choose(page: Page, label: string, option: string) {
  await page.getByRole("button", { name: new RegExp(`^${label}:`) }).click();
  await page.getByRole("menuitemradio", { name: option }).click();
}

async function openOlympus(page: Page, tab?: string) {
  await page.goto("/");
  await page.getByTestId("open-olympus-view").click();
  await expect(page.getByTestId("olympus-page")).toBeVisible({
    timeout: 10_000,
  });
  if (tab) await page.getByTestId(`olympus-tab-${tab}`).click();
}

test("the sidebar has no Agents item and local agents live in Olympus", async ({
  page,
}) => {
  await installMockBridge(page, {
    olympusEvents: [...olympusDevEvents(), ...olympusOpsEvents()],
  });
  await openOlympus(page);
  await expect(
    page.getByTestId("sidebar-primary-menu").getByText("Agents", {
      exact: true,
    }),
  ).toHaveCount(0);
  await expect(page.getByTestId("open-olympus-view")).toHaveAttribute(
    "data-active",
    "true",
  );
  await expect(page.getByTestId("olympus-tab-agents")).toBeVisible();
  await expect(page.getByTestId("olympus-tab-local")).toHaveCount(0);
});

test("the On this Mac tab shows the local agents", async ({ page }) => {
  await installMockBridge(page, {
    olympusEvents: [...olympusDevEvents(), ...olympusOpsEvents()],
    managedAgents: [
      {
        pubkey: TEST_IDENTITIES.charlie.pubkey,
        name: "Hack Day Helper",
        status: "running",
        channelNames: ["general"],
      },
    ],
  });
  await openOlympus(page, "local");
  await expect(page).toHaveURL(/tab=local/);
  const local = page.getByTestId("olympus-local-agents");
  await expect(
    local.getByRole("heading", { name: "Agents on this Mac" }),
  ).toBeVisible();
  await expect(local).toContainText("Hack Day Helper");
  await expect(local.getByTestId("olympus-agents-link")).toHaveCount(0);
  await expect(page.getByTestId("open-olympus-view")).toHaveAttribute(
    "data-active",
    "true",
  );
  await page.screenshot({ path: `${SHOTS}/01-local-tab.png` });
  await page.setViewportSize({ width: 900, height: 700 });
  const tabs = page.getByRole("tablist", { name: "Olympus sections" });
  await expect(page.getByTestId("olympus-tab-local")).toBeInViewport();
  expect(
    await tabs.evaluate((node) => node.scrollWidth <= node.clientWidth + 1),
  ).toBe(true);
  await page.screenshot({ path: `${SHOTS}/01b-local-tab-900.png` });
});

test("the schedules filter by agent and workspace is remembered", async ({
  page,
}) => {
  await installMockBridge(page, {
    olympusEvents: [...olympusDevEvents(), ...olympusOpsEvents()],
  });
  await openOlympus(page, "schedules");
  const olympus = page.getByTestId("olympus-page");
  await expect(olympus.getByTestId("olympus-schedule-ping")).toBeVisible();
  await choose(page, "Agent", "Argus · ops");
  await expect(olympus.getByTestId("olympus-schedule-ping")).toHaveCount(0);
  await expect(
    olympus.getByTestId("olympus-schedule-argus-report"),
  ).toBeVisible();
  await expect(olympus.getByTestId("olympus-schedule-filters")).toContainText(
    "2 of 3 schedules, 1 with a failed last run",
  );
  await page.screenshot({ path: `${SHOTS}/02-schedules-agent.png` });

  await page.reload();
  await expect(
    olympus.getByTestId("olympus-schedule-argus-report"),
  ).toBeVisible({ timeout: 10_000 });
  await expect(olympus.getByTestId("olympus-schedule-ping")).toHaveCount(0);
  await expect(
    page.getByRole("button", { name: "Agent: Argus · ops" }),
  ).toBeVisible();

  await choose(page, "Workspace", "dev");
  await expect(olympus.getByTestId("olympus-schedule-ping")).toBeVisible();
  await expect(
    olympus.getByTestId("olympus-schedule-argus-report"),
  ).toHaveCount(0);
  await expect(
    page.getByRole("button", { name: "Agent: All agents" }),
  ).toBeVisible();

  await olympus.getByLabel("Only failed").click();
  await expect(
    olympus.getByTestId("olympus-schedules-none-match"),
  ).toBeVisible();
  await olympus.getByRole("button", { name: "Show all schedules" }).click();
  await expect(olympus.getByTestId("olympus-schedule-ping")).toBeVisible();
  await expect(
    olympus.getByTestId("olympus-schedule-argus-report"),
  ).toBeVisible();
});

test("proposals open on Pending and link to all when none waits", async ({
  page,
}) => {
  const now = Math.floor(Date.now() / 1000);
  await installMockBridge(page, {
    olympusEvents: [
      ...olympusDevEvents(),
      olympusProposalEvent({
        phase: "applied",
        result: { reason: "applied", request: "r1", at: now - 60 },
      }),
    ],
  });
  await openOlympus(page, "proposals");
  await expect(
    page.getByTestId("olympus-proposal-filter-pending"),
  ).toHaveAttribute("aria-pressed", "true", { timeout: 15_000 });
  const empty = page.getByTestId("olympus-proposals-empty");
  await expect(empty).toContainText("Nothing waits for your decision");
  await page.screenshot({ path: `${SHOTS}/03-proposals-pending-empty.png` });
  await page.getByTestId("olympus-proposals-show-all").click();
  await expect(page.getByTestId("olympus-proposal-filter-all")).toHaveAttribute(
    "aria-pressed",
    "true",
  );
  await expect(
    page.getByTestId("olympus-proposal-p-aada7279a890"),
  ).toBeVisible();
});

test("providers show their description and the editor offers allowed models", async ({
  page,
}) => {
  await installMockBridge(page, {
    olympusEvents: [...olympusDevEvents(), ...olympusOpsEvents()],
  });
  await openOlympus(page, "providers");
  await expect(
    page.getByTestId("olympus-provider-description-claude"),
  ).toHaveText("Claude subscription through Hecate, flat rate");
  await expect(
    page.getByTestId("olympus-provider-description-codex"),
  ).toHaveCount(0);
  await page.screenshot({ path: `${SHOTS}/04-providers.png` });
});

test("the model field offers the models that the provider allows", async ({
  page,
}) => {
  const events = olympusOpsEvents().map((event) => {
    const content = JSON.parse(event.content);
    if (event.kind !== 30190 || content.name !== "argus") return event;
    content.gitopsFields = content.gitopsFields.filter(
      (field: string) => field !== "spec.model",
    );
    return { ...event, content: JSON.stringify(content) };
  });
  await installMockBridge(page, {
    olympusEvents: [...olympusDevEvents(), ...events],
  });
  await openOlympus(page);
  await page.getByTestId("olympus-agent-row-argus").click();
  await page
    .getByTestId("olympus-agent-page")
    .getByRole("button", { name: "Edit" })
    .click();
  const editor = page.getByTestId("olympus-agent-editor");
  await expect(editor.getByTestId("olympus-editor-model-hint")).toHaveText(
    "Models that the claude provider allows.",
  );
  await editor.getByRole("button", { name: "Model: claude-opus-5-5" }).click();
  await expect(page.getByRole("menuitemradio")).toHaveText([
    "claude-opus-5-5",
    "claude-sonnet-5-5",
  ]);
  await page.screenshot({ path: `${SHOTS}/05-editor-model.png` });
  await page.getByRole("menuitemradio", { name: "claude-sonnet-5-5" }).click();
  await editor.getByRole("button", { name: "Save changes" }).click();
  await expect
    .poll(() =>
      page.evaluate(() => window.__BUZZ_E2E_OLYMPUS_REQUESTS__?.length ?? 0),
    )
    .toBe(1);
  const request = await page.evaluate(
    () => window.__BUZZ_E2E_OLYMPUS_REQUESTS__?.[0],
  );
  expect(JSON.parse(request?.content ?? "")).toMatchObject({
    action: "patch",
    agent: "argus",
    patch: { model: "claude-sonnet-5-5" },
  });
});
