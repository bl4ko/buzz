import { expect, type Page, test } from "@playwright/test";

import { installMockBridge } from "../helpers/bridge";
import {
  olympusDevEvents,
  olympusProofEvent,
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
  await expect(details).toContainText("share: upload_file, list_files");
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
  await expect
    .poll(() =>
      page.evaluate(
        () =>
          window.__BUZZ_E2E_HAS_MOCK_GLOBAL_KIND_SUBSCRIPTION__?.(30190) ??
          false,
      ),
    )
    .toBe(true);
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
