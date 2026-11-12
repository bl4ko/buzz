import { expect, type Page, test } from "@playwright/test";

import { installMockBridge } from "../helpers/bridge";
import {
  OLYMPUS_OPERATOR,
  OLYMPUS_OWNER,
  olympusDevEvents,
  olympusProofEvent,
  olympusResultEvent,
  PROOF_PUBLIC_KEY,
} from "../helpers/olympus";

async function openAgentsPage(page: Page) {
  await installMockBridge(page, { olympusEvents: olympusDevEvents() });
  await page.goto("/");
  await page.getByTestId("open-agents-view").click();
  const section = page.getByTestId("olympus-agents-section");
  await expect(section).toBeVisible({ timeout: 10_000 });
  return section;
}

async function waitForOlympusLiveSubscription(page: Page) {
  await expect
    .poll(
      () =>
        page.evaluate(
          () =>
            window.__BUZZ_E2E_HAS_MOCK_GLOBAL_KIND_SUBSCRIPTION__?.(30190) ??
            false,
        ),
      { timeout: 15_000 },
    )
    .toBe(true);
}

test("shows Olympus agents grouped by workspace", async ({ page }) => {
  const section = await openAgentsPage(page);
  await expect(
    section.getByRole("heading", { name: "Olympus agents" }),
  ).toBeVisible();

  const workspace = section.getByTestId("olympus-workspace-dev");
  await expect(workspace.getByRole("heading", { name: "dev" })).toBeVisible();
  await expect(workspace.getByText("Ready", { exact: true })).toBeVisible();

  const proof = workspace.getByTestId("olympus-agent-row-proof");
  await expect(proof).toContainText("claude-code · claude-haiku-5-5");
  await expect(proof).toContainText("Online");
  await expect(proof).toContainText("share");
  await expect(proof).toContainText("Memory private");
  await expect(proof).toContainText("Active 2m ago");

  const codex = workspace.getByTestId("olympus-agent-row-codex2");
  await expect(codex).toContainText("codex · gpt-5.5");
  await expect(codex).toContainText("Suspended");
  await expect(codex).toContainText("Suspended by the owner");
  await expect(codex).toContainText("No MCP servers");
});

test("opens the details panel with the full config", async ({ page }) => {
  const section = await openAgentsPage(page);
  await section.getByTestId("olympus-agent-row-proof").click();

  const details = page.getByTestId("olympus-agent-details");
  await expect(details.getByRole("heading", { name: "proof" })).toBeVisible();
  await expect(details.getByTestId("olympus-agent-instructions")).toContainText(
    "Answer pings in the workspace channel.",
  );
  await expect(details).toContainText("upload_file, list_files");
  await expect(details).toContainText("Memory bank: private.");
  await expect(details).toContainText("proof-notes (write)");
  await expect(details).toContainText("skills/buzz");
  await expect(details).toContainText("share.xqx.uk on ports 443");
  await expect(details).toContainText("*/5 * * * *");
  await expect(details).toContainText("Europe/Ljubljana");
  await expect(details).toContainText("Prompt: Post a short status line.");
  await expect(details).toContainText("Succeeded");
  await expect(
    details.getByRole("row", { name: /Online True Connected/ }),
  ).toBeVisible();
  await expect(details.getByTestId("olympus-agent-public-key")).toHaveText(
    PROOF_PUBLIC_KEY,
  );
  await expect(
    details.getByRole("button", { name: "Copy agent public key" }),
  ).toBeVisible();

  await details.getByRole("button", { name: "Profile" }).click();
  await expect(details).toBeHidden();
  await expect(page).toHaveURL(new RegExp(`profile=${PROOF_PUBLIC_KEY}`));
});

test("hides the section when the relay has no Olympus events", async ({
  page,
}) => {
  await installMockBridge(page);
  await page.goto("/");
  await page.getByTestId("open-agents-view").click();
  await expect(page.getByTestId("unified-agents-groups")).toBeVisible({
    timeout: 10_000,
  });
  await expect(page.getByTestId("olympus-agents-section")).toHaveCount(0);
});

test("applies live agent updates and tombstones", async ({ page }) => {
  const section = await openAgentsPage(page);
  await waitForOlympusLiveSubscription(page);
  const suspended = olympusProofEvent({ phase: "Suspended" });
  suspended.created_at += 10;
  await page.evaluate((event) => {
    window.__BUZZ_E2E_EMIT_MOCK_OLYMPUS_EVENT__?.(event);
  }, suspended);
  const proof = section.getByTestId("olympus-agent-row-proof");
  await expect(proof).toContainText("Suspended");

  const tombstone = {
    ...suspended,
    id: "f".repeat(64),
    created_at: suspended.created_at + 1,
    content: "",
    tags: suspended.tags.map((tag) =>
      tag[0] === "status" ? ["status", "deleted"] : tag,
    ),
  };
  await page.evaluate((event) => {
    window.__BUZZ_E2E_EMIT_MOCK_OLYMPUS_EVENT__?.(event);
  }, tombstone);
  await expect(proof).toHaveCount(0);
  await expect(section.getByTestId("olympus-agent-row-codex2")).toBeVisible();
});

async function waitForOlympusRequest(page: Page, count: number) {
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

async function emitOlympusEvent(page: Page, event: unknown) {
  await page.evaluate((value) => {
    window.__BUZZ_E2E_EMIT_MOCK_OLYMPUS_EVENT__?.(
      value as Parameters<
        NonNullable<typeof window.__BUZZ_E2E_EMIT_MOCK_OLYMPUS_EVENT__>
      >[0],
    );
  }, event);
}

test("suspends an agent through a signed change request", async ({ page }) => {
  const section = await openAgentsPage(page);
  await section.getByTestId("olympus-agent-row-proof").click();
  const details = page.getByTestId("olympus-agent-details");
  const suspend = details.getByRole("button", { name: "Suspend" });
  await suspend.click();

  const status = details.getByTestId("olympus-agent-request-status");
  await expect(status).toContainText("Suspend: waiting for Hephaestus");
  await expect(suspend).toBeDisabled();
  await expect(details.getByRole("button", { name: "Edit" })).toBeDisabled();

  const request = await waitForOlympusRequest(page, 1);
  expect(request?.kind).toBe(44310);
  expect(request?.pubkey).toBe(OLYMPUS_OWNER);
  expect(request?.tags).toEqual([
    ["p", OLYMPUS_OPERATOR],
    ["workspace", "dev"],
    ["agent", "proof"],
    ["action", "suspend"],
  ]);
  expect(JSON.parse(request?.content ?? "")).toEqual({
    v: 1,
    action: "suspend",
    workspace: "dev",
    agent: "proof",
  });

  await emitOlympusEvent(
    page,
    olympusResultEvent({
      requestId: request?.id ?? "",
      status: "accepted",
      reason: "applied",
      action: "suspend",
      agent: "proof",
    }),
  );
  await expect(status).toContainText("Suspend: accepted (applied)");
  await waitForOlympusLiveSubscription(page);
  const suspended = olympusProofEvent({ phase: "Suspended" });
  suspended.created_at += 10;
  await emitOlympusEvent(page, suspended);
  await expect(details.getByRole("button", { name: "Resume" })).toBeEnabled();
  await expect(
    details.getByRole("row", { name: /Online False Suspended/ }),
  ).toBeVisible();
  await expect(section.getByTestId("olympus-agent-row-proof")).toContainText(
    "Suspended",
  );
});

test("shows the reason of a refused change", async ({ page }) => {
  const section = await openAgentsPage(page);
  await section.getByTestId("olympus-agent-row-proof").click();
  const details = page.getByTestId("olympus-agent-details");
  await details.getByRole("button", { name: "Edit" }).click();
  const form = details.getByTestId("olympus-agent-edit-form");
  await form.getByLabel("Model").selectOption("claude-opus-5-5");
  await form.getByLabel("Effort").selectOption("");
  await form.getByRole("button", { name: "Save changes" }).click();

  const request = await waitForOlympusRequest(page, 1);
  expect(JSON.parse(request?.content ?? "")).toEqual({
    v: 1,
    action: "update",
    workspace: "dev",
    agent: "proof",
    model: "claude-opus-5-5",
    effort: null,
  });
  await emitOlympusEvent(
    page,
    olympusResultEvent({
      requestId: request?.id ?? "",
      status: "refused",
      reason: "model is not in the pool anthropic",
      action: "update",
      agent: "proof",
    }),
  );
  const status = details.getByTestId("olympus-agent-request-status");
  await expect(status).toContainText(
    "Edit: refused. model is not in the pool anthropic",
  );
  await expect(details.getByRole("button", { name: "Edit" })).toBeEnabled();
});

test("adds an MCP server and creates an agent", async ({ page }) => {
  const section = await openAgentsPage(page);
  await section.getByTestId("olympus-agent-row-proof").click();
  const details = page.getByTestId("olympus-agent-details");
  const mcpSelect = details.getByLabel("MCP server to add");
  await expect(mcpSelect.locator("option")).toHaveText(["search"]);
  await details.getByRole("button", { name: "Add MCP server" }).click();
  const addMcp = await waitForOlympusRequest(page, 1);
  expect(JSON.parse(addMcp?.content ?? "").server).toEqual({ name: "search" });
  await page.keyboard.press("Escape");
  await expect(details).toBeHidden();

  const workspace = section.getByTestId("olympus-workspace-dev");
  await workspace.getByRole("button", { name: "New agent in dev" }).click();
  const dialog = page.getByTestId("olympus-new-agent-dialog");
  await dialog.getByLabel("Name").fill("Bad_Name");
  await expect(dialog.getByText(/Use lowercase letters/)).toBeVisible();
  await expect(
    dialog.getByRole("button", { name: "Create agent" }),
  ).toBeDisabled();
  await dialog.getByLabel("Name").fill("scout");
  await dialog.getByLabel("Harness").selectOption("codex");
  await dialog.getByLabel("Pool").selectOption("openai");
  await dialog.getByLabel("Model").fill("gpt-5.5");
  await dialog.getByLabel("Effort").selectOption("low");
  await dialog.getByRole("button", { name: "Create agent" }).click();
  await expect(dialog).toBeHidden();

  const create = await waitForOlympusRequest(page, 2);
  expect(create?.tags).toEqual([
    ["p", OLYMPUS_OPERATOR],
    ["workspace", "dev"],
    ["agent", "scout"],
    ["action", "create"],
  ]);
  expect(JSON.parse(create?.content ?? "")).toEqual({
    v: 1,
    action: "create",
    workspace: "dev",
    agent: "scout",
    harness: "codex",
    pool: "openai",
    model: "gpt-5.5",
    effort: "low",
  });
  await expect(
    workspace.getByTestId("olympus-create-request-dev"),
  ).toContainText("New agent: waiting for Hephaestus");
  await expect(
    workspace.getByRole("button", { name: "New agent in dev" }),
  ).toBeDisabled();
});
