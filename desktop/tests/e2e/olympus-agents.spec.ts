import { expect, type Page, test } from "@playwright/test";

import { installMockBridge } from "../helpers/bridge";
import {
  OLYMPUS_OPERATOR,
  OLYMPUS_OWNER,
  olympusDevEvents,
  olympusProofEvent,
  olympusResultEvent,
} from "../helpers/olympus";
import {
  olympusArgusEvent,
  olympusOpsEvents,
  olympusOpsResult,
} from "../helpers/olympusPage";

async function openOlympus(page: Page, events = olympusOpsEvents()) {
  await installMockBridge(page, {
    olympusEvents: [...olympusDevEvents(), ...events],
  });
  await page.goto("/");
  await page.getByTestId("open-olympus-view").click();
  await expect(page.getByTestId("olympus-page")).toBeVisible({
    timeout: 10_000,
  });
  return page.getByTestId("olympus-page");
}

async function waitForLive(page: Page) {
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

async function emit(page: Page, event: unknown) {
  await page.evaluate((value) => {
    window.__BUZZ_E2E_EMIT_MOCK_OLYMPUS_EVENT__?.(
      value as Parameters<
        NonNullable<typeof window.__BUZZ_E2E_EMIT_MOCK_OLYMPUS_EVENT__>
      >[0],
    );
  }, event);
}

async function choose(page: Page, label: string, option: string) {
  await page.getByRole("button", { name: new RegExp(`^${label}:`) }).click();
  await page.getByRole("menuitemradio", { name: option }).click();
}

test("lists workspaces and agents on the Olympus page", async ({ page }) => {
  const olympus = await openOlympus(page);
  await expect(page.getByTestId("olympus-summary")).toHaveText(
    "2 workspaces · 4 agents · 1 failed schedule",
  );
  const ops = olympus.getByTestId("olympus-workspace-ops");
  await expect(ops.getByRole("heading", { name: "ops" })).toBeVisible();
  const argus = ops.getByTestId("olympus-agent-row-argus");
  await expect(argus).toContainText("Argus");
  await expect(argus).toContainText("claude-code · claude-opus-5-5 · high");
  await expect(argus).toContainText("1 failed");
  await expect(argus).toHaveAccessibleName(/Argus, Online, .*1 failed/);
  await expect(ops.getByTestId("olympus-agent-row-zeus")).toContainText(
    "Master",
  );
  await expect(
    ops.getByRole("button", { name: "Suspend workspace ops" }),
  ).toBeEnabled();
  await expect(
    olympus
      .getByTestId("olympus-workspace-dev")
      .getByTestId("olympus-agent-row-proof"),
  ).toContainText("Online");
});

test("shows the empty state when the relay has no Olympus state", async ({
  page,
}) => {
  await installMockBridge(page);
  await page.goto("/");
  await page.getByTestId("open-olympus-view").click();
  await expect(page.getByTestId("olympus-no-state")).toContainText(
    "No Olympus state from this relay",
  );
  await page.getByTestId("open-agents-view").click();
  await expect(page.getByTestId("olympus-agents-link")).toHaveCount(0);
});

test("the agent page shows the full config and locks git fields", async ({
  page,
}) => {
  const olympus = await openOlympus(page);
  await olympus.getByTestId("olympus-agent-row-argus").click();
  const agent = page.getByTestId("olympus-agent-page");
  await expect(
    agent.getByRole("heading", { level: 1, name: /Argus/ }),
  ).toBeVisible();
  await expect(page).toHaveURL(/#\/olympus\/ops\/argus/);
  await expect(agent).toContainText("grafana-token → GRAFANA_TOKEN");
  await expect(agent).toContainText("cluster-reader");
  await expect(agent).toContainText("Mode hosts");
  await expect(agent).toContainText("api.github.com on ports 443");
  await expect(agent).toContainText("requests: cpu 250m · limits: memory 2Gi");
  await expect(agent).toContainText("agents/argus/agents/argus.md");
  await expect(agent).toContainText("10Gi");
  await expect(agent.getByTestId("olympus-lock-Model")).toBeVisible();
  await expect(agent.getByTestId("olympus-lock-Storage")).toHaveCount(0);
  await expect(
    agent.getByRole("button", { name: "Remove MCP server share" }),
  ).toHaveCount(0);
  await expect(agent.getByRole("button", { name: "Delete" })).toHaveCount(0);
  await expect(
    agent.getByTestId("olympus-schedule-daily-os-updates"),
  ).toContainText("Script as the agent");
});

test("suspends a git agent and records the result", async ({ page }) => {
  const olympus = await openOlympus(page);
  await olympus.getByTestId("olympus-agent-row-argus").click();
  const agent = page.getByTestId("olympus-agent-page");
  await waitForLive(page);
  await agent.getByRole("button", { name: "Suspend", exact: true }).click();
  const request = await waitForRequest(page, 1);
  expect(request?.pubkey).toBe(OLYMPUS_OWNER);
  expect(request?.tags).toEqual([
    ["p", OLYMPUS_OPERATOR],
    ["workspace", "ops"],
    ["agent", "argus"],
    ["action", "suspend"],
  ]);
  await emit(
    page,
    olympusOpsResult({
      requestId: request?.id ?? "",
      status: "accepted",
      reason: "applied",
      action: "suspend",
      agent: "argus",
    }),
  );
  await expect(agent.getByTestId("olympus-agent-request-status")).toContainText(
    "Suspend: accepted (applied)",
  );
  const suspended = olympusArgusEvent({ suspend: true });
  suspended.created_at += 10;
  await emit(page, suspended);
  await expect(
    agent.getByRole("button", { name: "Resume", exact: true }),
  ).toBeEnabled();
  await expect(agent.getByTestId("olympus-agent-history")).toContainText(
    "Suspend",
  );
  await expect(agent.getByTestId("olympus-agent-history")).toContainText(
    "Accepted: applied",
  );
});

test("edits fields that git does not own with a patch", async ({ page }) => {
  const olympus = await openOlympus(page);
  await olympus.getByTestId("olympus-agent-row-argus").click();
  const agent = page.getByTestId("olympus-agent-page");
  await agent.getByRole("button", { name: "Edit" }).click();
  const editor = page.getByTestId("olympus-agent-editor");
  await expect(
    editor.getByRole("textbox", { name: "Display name" }),
  ).toBeDisabled();
  await expect(
    editor.getByRole("textbox", { name: "Instructions" }),
  ).toBeDisabled();
  await editor.getByRole("textbox", { name: "Storage" }).fill("20Gi");
  await editor.getByRole("button", { name: "Save changes" }).click();
  await expect(editor).toBeHidden();
  const request = await waitForRequest(page, 1);
  expect(JSON.parse(request?.content ?? "")).toEqual({
    v: 1,
    action: "patch",
    workspace: "ops",
    agent: "argus",
    patch: { storage: "20Gi" },
  });
});

test("a high-risk spec change needs a second confirmation", async ({
  page,
}) => {
  const olympus = await openOlympus(page);
  await olympus.getByTestId("olympus-agent-row-argus").click();
  const agent = page.getByTestId("olympus-agent-page");
  await agent.getByRole("button", { name: "Edit" }).click();
  const editor = page.getByTestId("olympus-agent-editor");
  await editor.getByRole("tab", { name: "Spec JSON" }).click();
  const json = editor.getByLabel("Spec fields that Olympus manages");
  const spec = JSON.parse(await json.inputValue());
  expect(spec.model).toBeUndefined();
  expect(spec.storage).toBe("10Gi");
  await json.fill(JSON.stringify({ ...spec, model: "x" }));
  await editor.getByRole("button", { name: "Save spec" }).click();
  await expect(editor.getByRole("alert")).toContainText(
    "These fields are set in gitops-home: model.",
  );
  await json.fill(JSON.stringify({ ...spec, runtimeClass: "gvisor" }));
  await editor.getByRole("button", { name: "Save spec" }).click();
  const risk = page.getByTestId("olympus-risk-dialog");
  await expect(risk).toContainText("runtime class");
  await risk.getByRole("button", { name: "Cancel" }).click();
  await expect(risk).toBeHidden();
  expect(
    await page.evaluate(() => window.__BUZZ_E2E_OLYMPUS_REQUESTS__?.length),
  ).toBe(0);
  await editor.getByRole("button", { name: "Save spec" }).click();
  await risk.getByRole("button", { name: "Confirm high-risk change" }).click();
  const request = await waitForRequest(page, 1);
  expect(JSON.parse(request?.content ?? "")).toEqual({
    v: 1,
    action: "patch",
    workspace: "ops",
    agent: "argus",
    patch: { runtimeClass: "gvisor" },
    highRisk: true,
  });
});

test("the schedules tab shows next runs, failures, and actions", async ({
  page,
}) => {
  const olympus = await openOlympus(page);
  await olympus.getByTestId("olympus-tab-schedules").click();
  await expect(page).toHaveURL(/tab=schedules/);
  const failed = olympus.getByTestId("olympus-schedule-daily-os-updates");
  await expect(failed).toContainText("Failed");
  await expect(failed).toContainText("30 6 * * *");
  await expect(failed).toContainText(/in \d+/);
  await olympus.getByLabel("Only failed").click();
  await expect(
    olympus.getByTestId("olympus-schedule-argus-report"),
  ).toHaveCount(0);
  await expect(olympus.getByTestId("olympus-schedule-ping")).toHaveCount(0);
  await failed
    .getByRole("button", { name: "Run schedule daily-os-updates now" })
    .click();
  const run = await waitForRequest(page, 1);
  expect(run?.tags).toEqual([
    ["p", OLYMPUS_OPERATOR],
    ["workspace", "ops"],
    ["schedule", "daily-os-updates"],
    ["action", "run-now"],
  ]);
  await emit(
    page,
    olympusOpsResult({
      requestId: run?.id ?? "",
      status: "accepted",
      reason: "started",
      action: "run-now",
      schedule: "daily-os-updates",
    }),
  );
  await expect(
    olympus.getByTestId("olympus-schedule-request-daily-os-updates"),
  ).toContainText("Run now: accepted (started)");
  await failed
    .getByRole("button", { name: "Suspend schedule daily-os-updates" })
    .click();
  const suspend = await waitForRequest(page, 2);
  expect(JSON.parse(suspend?.content ?? "")).toEqual({
    v: 1,
    action: "suspend-schedule",
    workspace: "ops",
    schedule: "daily-os-updates",
  });
});

test("creates an agent from a template and clones an agent", async ({
  page,
}) => {
  const olympus = await openOlympus(page);
  const ops = olympus.getByTestId("olympus-workspace-ops");
  await ops.getByRole("button", { name: "New agent in ops" }).click();
  const dialog = page.getByTestId("olympus-new-agent-dialog");
  await choose(page, "Start from", "Template ops-base");
  await dialog.getByLabel("Name", { exact: true }).fill("scout");
  await expect(
    dialog.getByRole("button", { name: /^Model: claude-sonnet-5-5/ }),
  ).toBeVisible();
  await choose(page, "Harness", "codex");
  await expect(
    dialog.getByRole("button", { name: /^Model pool: codex/ }),
  ).toBeVisible();
  await choose(page, "Harness", "claude-code");
  await choose(page, "Model", "claude-sonnet-5-5");
  await dialog.getByRole("button", { name: "Create agent" }).click();
  const risk = page.getByTestId("olympus-risk-dialog");
  await expect(risk).toContainText("agent template");
  await risk.getByRole("button", { name: "Confirm high-risk change" }).click();
  const create = await waitForRequest(page, 1);
  expect(create?.tags).toEqual([
    ["p", OLYMPUS_OPERATOR],
    ["workspace", "ops"],
    ["agent", "scout"],
    ["action", "create"],
  ]);
  expect(JSON.parse(create?.content ?? "")).toMatchObject({
    spec: { template: "ops-base" },
    highRisk: true,
  });
});

test("cloning an agent with secrets needs a confirmation", async ({ page }) => {
  const olympus = await openOlympus(page);
  await olympus.getByTestId("olympus-agent-row-argus").click();
  await page
    .getByTestId("olympus-agent-page")
    .getByRole("button", { name: "Clone" })
    .click();
  const dialog = page.getByTestId("olympus-new-agent-dialog");
  await expect(dialog.getByLabel("Name", { exact: true })).toHaveValue(
    "argus-copy",
  );
  await dialog.getByRole("button", { name: "Create agent" }).click();
  const risk = page.getByTestId("olympus-risk-dialog");
  await expect(risk).toContainText("secrets");
  await expect(risk).toContainText("Kubernetes role");
  await risk.getByRole("button", { name: "Confirm high-risk change" }).click();
  const create = await waitForRequest(page, 1);
  const content = JSON.parse(create?.content ?? "");
  expect(content.highRisk).toBe(true);
  expect(content.agent).toBe("argus-copy");
  expect(content.spec.secrets).toEqual([
    { name: "grafana-token", env: "GRAFANA_TOKEN" },
  ]);
  expect(content.spec.identityPath).toBeUndefined();
  expect(content.spec.profile).toBeUndefined();
});

test("an old operator keeps the old edit form for app agents", async ({
  page,
}) => {
  const olympus = await openOlympus(page);
  await olympus.getByTestId("olympus-agent-row-proof").click();
  const agent = page.getByTestId("olympus-agent-page");
  await agent.getByRole("button", { name: "Edit" }).click();
  const form = page.getByTestId("olympus-agent-edit-form");
  await form.getByLabel("Model").selectOption("claude-opus-5-5");
  await form.getByRole("button", { name: "Save changes" }).click();
  const request = await waitForRequest(page, 1);
  expect(JSON.parse(request?.content ?? "")).toEqual({
    v: 1,
    action: "update",
    workspace: "dev",
    agent: "proof",
    model: "claude-opus-5-5",
  });
  await emit(
    page,
    olympusResultEvent({
      requestId: request?.id ?? "",
      status: "refused",
      reason: "model not permitted",
      action: "update",
      agent: "proof",
    }),
  );
  await expect(agent.getByTestId("olympus-agent-request-status")).toContainText(
    "Edit: refused. model not permitted",
  );
});

test("applies live updates and tombstones", async ({ page }) => {
  const olympus = await openOlympus(page);
  await waitForLive(page);
  const suspended = olympusProofEvent({ phase: "Suspended" });
  suspended.created_at += 10;
  await emit(page, suspended);
  const proof = olympus.getByTestId("olympus-agent-row-proof");
  await expect(proof).toContainText("Suspended");
  await emit(page, {
    ...suspended,
    id: "f".repeat(64),
    created_at: suspended.created_at + 1,
    content: "",
    tags: suspended.tags.map((tag) =>
      tag[0] === "status" ? ["status", "deleted"] : tag,
    ),
  });
  await expect(proof).toHaveCount(0);
});

test("providers and workspaces tabs list the inventory", async ({ page }) => {
  const olympus = await openOlympus(page);
  await olympus.getByTestId("olympus-tab-providers").click();
  const claude = olympus.getByTestId("olympus-provider-claude");
  await expect(claude).toContainText("claude-opus-5-5, claude-sonnet-5-5");
  await expect(claude.getByRole("button", { name: "ops/argus" })).toBeVisible();
  await expect(olympus.getByTestId("olympus-mcp-hindsight")).toContainText(
    "ops/argus",
  );
  await olympus.getByTestId("olympus-tab-workspaces").click();
  const ops = olympus.getByTestId("olympus-workspace-card-ops");
  await expect(ops).toContainText("cpu 8, memory 16Gi");
  await expect(ops).toContainText("ops-base");
  await expect(ops.getByRole("button", { name: "Open channel" })).toBeVisible();
});
