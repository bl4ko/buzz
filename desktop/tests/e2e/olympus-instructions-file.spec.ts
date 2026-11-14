import { expect, type Page, test } from "@playwright/test";

import { installMockBridge } from "../helpers/bridge";
import { olympusDevEvents, olympusResultEvent } from "../helpers/olympus";
import { olympusOpsEvents } from "../helpers/olympusPage";

const SHOTS = "test-results/olympus-instructions-file";
const PATH = "argus/agents/argus.md";
const HEAD = "0123456789abcdef0123456789abcdef01234567";
const OLD = "You are Argus.\nWatch the cluster.\nReport once a day.";
const MINE =
  "You are Argus.\nWatch the cluster and the backups.\nReport once a day.";

function events() {
  return olympusOpsEvents().map((event) => {
    const content = JSON.parse(event.content);
    if (event.kind !== 30190 || content.name !== "argus") return event;
    content.gitopsFields = [];
    content.instructionsFile = {
      repo: "agents",
      path: PATH,
      url: "http://localhost:3000/git/olympus-ops/agents.git",
      branch: "main",
    };
    return { ...event, content: JSON.stringify(content) };
  });
}

async function setFile(page: Page, text: string) {
  await page.evaluate(
    ({ path, value }) => {
      window.__BUZZ_E2E_PROJECT_REPO_FILE_CONTENTS__ = { [path]: value };
    },
    { path: PATH, value: text },
  );
}

async function requests(page: Page) {
  return page.evaluate(() => window.__BUZZ_E2E_OLYMPUS_REQUESTS__ ?? []);
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

async function openEditor(page: Page) {
  await installMockBridge(page, {
    olympusEvents: [...olympusDevEvents(), ...events()],
  });
  await page.goto("/");
  await setFile(page, OLD);
  await page.getByTestId("open-olympus-view").click();
  await page.getByTestId("olympus-agent-row-argus").click();
  await expect(
    page.getByTestId("olympus-agent-instructions-file"),
  ).toContainText(`agents/${PATH}`);
  await page
    .getByTestId("olympus-agent-page")
    .getByRole("button", { name: "Edit" })
    .click();
  const editor = page.getByTestId("olympus-agent-editor");
  await expect(editor).toContainText("Olympus manages every field");
  const field = editor.getByRole("textbox", { name: "Instructions" });
  await expect(field).toHaveValue(OLD);
  await expect(editor.getByTestId("olympus-instructions-file")).toContainText(
    "0123456",
  );
  return { editor, field };
}

test("instructions from Olympus git save through edit-file after a diff", async ({
  page,
}) => {
  const { editor, field } = await openEditor(page);
  await field.fill(MINE);
  await page.screenshot({ path: `${SHOTS}/01-editor.png` });
  await editor.getByRole("button", { name: "Review and save" }).click();
  const review = page.getByTestId("olympus-instructions-review");
  const diff = review.getByTestId("olympus-file-diff");
  await expect(diff.locator('[data-line="del"]')).toContainText([
    "Watch the cluster.",
  ]);
  await expect(diff.locator('[data-line="add"]')).toContainText([
    "Watch the cluster and the backups.",
  ]);
  await page.screenshot({ path: `${SHOTS}/02-review.png` });
  await review.getByLabel("Commit message").fill("docs: argus watches backups");
  await review.getByTestId("olympus-instructions-commit").click();
  await expect.poll(async () => (await requests(page)).length).toBe(1);
  const [request] = await requests(page);
  expect(request?.tags).toEqual([
    ["p", expect.any(String)],
    ["workspace", "ops"],
    ["action", "edit-file"],
  ]);
  expect(JSON.parse(request?.content ?? "")).toEqual({
    v: 1,
    action: "edit-file",
    workspace: "ops",
    repo: "agents",
    path: PATH,
    content: MINE,
    base: HEAD,
    message: "docs: argus watches backups",
  });
  await expect(
    review.getByTestId("olympus-instructions-commit"),
  ).toBeDisabled();
  await emit(
    page,
    olympusResultEvent({
      requestId: request?.id ?? "",
      status: "accepted",
      reason: "committed",
      action: "edit-file",
      commit: "fedcba9876543210fedcba9876543210fedcba98",
    }),
  );
  await expect(review).toBeHidden();
  await expect(editor).toBeHidden();
  await expect(
    page.getByText("Instructions committed (fedcba9)"),
  ).toBeVisible();
});

test("a changed file shows the git version and can keep my text", async ({
  page,
}) => {
  const { editor, field } = await openEditor(page);
  await field.fill(MINE);
  await editor.getByRole("button", { name: "Review and save" }).click();
  const review = page.getByTestId("olympus-instructions-review");
  await review.getByTestId("olympus-instructions-commit").click();
  await expect.poll(async () => (await requests(page)).length).toBe(1);
  const [first] = await requests(page);
  await setFile(page, `${OLD}\nUse UTC.`);
  await emit(
    page,
    olympusResultEvent({
      requestId: first?.id ?? "",
      status: "refused",
      reason: "the file changed",
      action: "edit-file",
    }),
  );
  await expect(review).toContainText("The file changed in git");
  await expect(
    review.getByTestId("olympus-file-diff").locator('[data-line="del"]'),
  ).toContainText(["Watch the cluster.", "Use UTC."]);
  await page.screenshot({ path: `${SHOTS}/03-conflict.png` });
  await review.getByRole("button", { name: "Keep my text" }).click();
  await expect(review).toContainText("Review the instructions change");
  await review.getByTestId("olympus-instructions-commit").click();
  await expect.poll(async () => (await requests(page)).length).toBe(2);
  const second = (await requests(page))[1];
  expect(JSON.parse(second?.content ?? "").content).toBe(MINE);

  await emit(
    page,
    olympusResultEvent({
      requestId: second?.id ?? "",
      status: "refused",
      reason: "edit failed: push failed: requires admin role",
      action: "edit-file",
    }),
  );
  await expect(review.getByRole("alert")).toContainText("requires admin role");
  await review.getByRole("button", { name: "Cancel" }).click();
  await expect(field).toHaveValue(MINE);
});

test("using the git version drops my text", async ({ page }) => {
  const { editor, field } = await openEditor(page);
  await field.fill(MINE);
  await editor.getByRole("button", { name: "Review and save" }).click();
  const review = page.getByTestId("olympus-instructions-review");
  await review.getByTestId("olympus-instructions-commit").click();
  await expect.poll(async () => (await requests(page)).length).toBe(1);
  const [first] = await requests(page);
  await setFile(page, `${OLD}\nUse UTC.`);
  await emit(
    page,
    olympusResultEvent({
      requestId: first?.id ?? "",
      status: "refused",
      reason: "the file changed",
      action: "edit-file",
    }),
  );
  await review.getByRole("button", { name: "Use the git version" }).click();
  await expect(review).toBeHidden();
  await expect(field).toHaveValue(`${OLD}\nUse UTC.`);
  await expect(
    editor.getByRole("button", { name: "Save changes" }),
  ).toBeDisabled();
});
