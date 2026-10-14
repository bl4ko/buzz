import { expect, test } from "@playwright/test";

import { TEST_IDENTITIES, installMockBridge } from "../helpers/bridge";

async function waitForMockLiveSubscription(
  page: import("@playwright/test").Page,
  channelName: string,
  exactChannel = false,
) {
  await expect
    .poll(async () => {
      return page.evaluate(
        ({ ch, exact }) =>
          (
            window as Window & {
              __BUZZ_E2E_HAS_MOCK_LIVE_SUBSCRIPTION__?: (input: {
                channelName: string;
                kind?: number;
                exactChannel?: boolean;
              }) => boolean;
            }
          ).__BUZZ_E2E_HAS_MOCK_LIVE_SUBSCRIPTION__?.(
            exact
              ? { channelName: ch, kind: 9, exactChannel: true }
              : { channelName: ch },
          ) ?? false,
        { ch: channelName, exact: exactChannel },
      );
    })
    .toBe(true);
}

function emitMockMessage(
  page: import("@playwright/test").Page,
  channelName: string,
  content: string,
  createdAt?: number,
) {
  return page.evaluate(
    ({ ch, msg, pubkey, ts }) => {
      (
        window as Window & {
          __BUZZ_E2E_EMIT_MOCK_MESSAGE__?: (input: {
            channelName: string;
            content: string;
            pubkey: string;
            createdAt?: number;
          }) => unknown;
        }
      ).__BUZZ_E2E_EMIT_MOCK_MESSAGE__?.({
        channelName: ch,
        content: msg,
        pubkey,
        createdAt: ts,
      });
    },
    {
      ch: channelName,
      msg: content,
      pubkey: TEST_IDENTITIES.alice.pubkey,
      ts: createdAt,
    },
  );
}

const SELF_PUBKEY = "deadbeef".repeat(8);

async function emitMockEvent(
  page: import("@playwright/test").Page,
  input: {
    content: string;
    createdAt: number;
    parentEventId?: string;
    pubkey: string;
  },
) {
  const event = await page.evaluate(
    (message) =>
      (
        window as Window & {
          __BUZZ_E2E_EMIT_MOCK_MESSAGE__?: (input: {
            channelName: string;
            content: string;
            createdAt: number;
            parentEventId?: string;
            pubkey: string;
          }) => { id: string } | undefined;
        }
      ).__BUZZ_E2E_EMIT_MOCK_MESSAGE__?.({
        channelName: "general",
        ...message,
      }),
    input,
  );
  if (!event) throw new Error("Mock message emitter is unavailable");
  return event;
}

async function seedUnreadThreadReplies(page: import("@playwright/test").Page) {
  await page.getByTestId("channel-general").click();
  await expect(page.getByTestId("chat-title")).toHaveText("general");
  await waitForMockLiveSubscription(page, "general", true);

  const now = Math.floor(Date.now() / 1000);
  const rootA = await emitMockEvent(page, {
    content: "Thread root A",
    createdAt: now - 20,
    pubkey: SELF_PUBKEY,
  });
  const rootB = await emitMockEvent(page, {
    content: "Thread root B",
    createdAt: now - 19,
    pubkey: SELF_PUBKEY,
  });

  await page.getByTestId("channel-random").click();
  await expect(page.getByTestId("chat-title")).toHaveText("random");
  await waitForMockLiveSubscription(page, "general", true);

  const base = unreadTimestamp();
  await emitMockEvent(page, {
    content: "Newer thread reply",
    createdAt: base + 1,
    parentEventId: rootB.id,
    pubkey: TEST_IDENTITIES.bob.pubkey,
  });
  await emitMockEvent(page, {
    content: "Oldest thread reply",
    createdAt: base,
    parentEventId: rootA.id,
    pubkey: TEST_IDENTITIES.alice.pubkey,
  });
  await expect(page.getByTestId("channel-unread-dot-general")).toBeVisible();
  return { base, rootAId: rootA.id };
}

// Unread messages must be created strictly after the read frontier captured
// when the channel was last open. The frontier is captured at the current
// second on open, and computeChannelUnreadMarker uses a strict
// `createdAt > frontier` predicate — so emitting at the same wall-clock second
// leaves the messages on the read side and the pill/divider never render.
// Dating them a minute ahead puts them deterministically past the frontier.
const UNREAD_OFFSET_SECONDS = 60;

function unreadTimestamp() {
  return Math.floor(Date.now() / 1000) + UNREAD_OFFSET_SECONDS;
}

// Emit `count` unread messages to general, staggered one second apart so they
// sort deterministically and all land strictly past the read frontier.
async function emitUnreadMessages(
  page: import("@playwright/test").Page,
  count: number,
) {
  const base = unreadTimestamp();
  for (let index = 0; index < count; index += 1) {
    await emitMockMessage(
      page,
      "general",
      `Unread message ${index + 1}`,
      base + index,
    );
  }
}

// A channel that was never opened has no read frontier, so it opens at the
// bottom and keeps the pill instead of jumping to its oldest unread message.
async function emitNeverReadMessages(
  page: import("@playwright/test").Page,
  count: number,
) {
  const base = Math.floor(Date.now() / 1000) - 600;
  for (let index = 0; index < count; index += 1) {
    await emitMockMessage(
      page,
      "random",
      `Never read message ${index + 1}`,
      base + index,
    );
  }
}

// Scroll the timeline up so the viewport is no longer pinned to the bottom.
// The pill auto-dismisses once the user reaches the bottom of the timeline, so
// it only stays rendered while scrolled up. Scrolling part-way (rather than to
// the very top) keeps real message context on screen instead of the channel's
// empty-state intro.
async function scrollTimelineUp(page: import("@playwright/test").Page) {
  await page.getByTestId("message-timeline").evaluate((el) => {
    el.scrollTop = Math.floor(el.scrollHeight * 0.35);
  });
  await page.waitForTimeout(300);
}

test.describe("unread pill & divider", () => {
  test("01-unread-pill-visible", async ({ page }) => {
    await installMockBridge(page);
    await page.goto("/");

    await page.getByTestId("channel-general").click();
    await expect(page.getByTestId("chat-title")).toHaveText("general");

    await emitNeverReadMessages(page, 20);

    await page.getByTestId("channel-random").click();
    await expect(page.getByTestId("chat-title")).toHaveText("random");

    // Scroll up so the unreads sit below the fold: the pill is the
    // "jump to oldest unread" affordance and only stays on screen while the
    // user is scrolled away from the bottom of the timeline.
    await scrollTimelineUp(page);

    const pill = page.getByTestId("message-unread-pill");
    await expect(pill).toBeVisible();
    await expect(pill).toContainText("20 new messages");
    await expect(
      page.getByTestId("message-timeline-sticky-day-divider"),
    ).toHaveAttribute("data-day-label", /.+/);

    const { pillTop, stickyDayTop } = await page.evaluate(() => {
      const pill = document.querySelector<HTMLElement>(
        '[data-testid="message-unread-pill"]',
      );
      const stickyDay = document.querySelector<HTMLElement>(
        '[data-testid="message-timeline-sticky-day-divider"]',
      );
      if (!pill || !stickyDay) {
        throw new Error("missing top timeline affordance");
      }
      return {
        pillTop: pill.getBoundingClientRect().top,
        stickyDayTop: stickyDay.getBoundingClientRect().top,
      };
    });
    expect(Math.abs(pillTop - stickyDayTop)).toBeLessThanOrEqual(1);
  });

  test("02-unread-divider-visible", async ({ page }) => {
    await installMockBridge(page);
    await page.goto("/");

    await page.getByTestId("channel-general").click();
    await expect(page.getByTestId("chat-title")).toHaveText("general");
    await waitForMockLiveSubscription(page, "general");

    await page.getByTestId("channel-random").click();
    await expect(page.getByTestId("chat-title")).toHaveText("random");

    await emitUnreadMessages(page, 3);

    await page.getByTestId("channel-general").click();
    await expect(page.getByTestId("chat-title")).toHaveText("general");

    const divider = page.getByTestId("message-unread-divider");
    await expect(divider).toBeVisible();

    // Scroll the divider into view before asserting it.
    await divider.scrollIntoViewIfNeeded();
    await page.waitForTimeout(300);
  });

  test("03-pill-dismissed-after-scroll", async ({ page }) => {
    await installMockBridge(page);
    await page.goto("/");

    await page.getByTestId("channel-general").click();
    await expect(page.getByTestId("chat-title")).toHaveText("general");

    await emitNeverReadMessages(page, 20);

    await page.getByTestId("channel-random").click();
    await expect(page.getByTestId("chat-title")).toHaveText("random");

    // Scroll up so the pill is showing, matching scenario 01's starting state.
    await scrollTimelineUp(page);

    const pill = page.getByTestId("message-unread-pill");
    await expect(pill).toBeVisible();

    // Click the pill to jump to the oldest unread, which dismisses it.
    await pill.click();

    // Pill should be dismissed
    await expect(pill).toHaveCount(0);
  });

  test("04-mark-unread-suppresses-pill", async ({ page }) => {
    await installMockBridge(page);
    await page.goto("/");

    await page.getByTestId("channel-general").click();
    await expect(page.getByTestId("chat-title")).toHaveText("general");

    // Mark channel unread via context menu on the sidebar item
    await page.getByTestId("channel-general").click({ button: "right" });
    await page.getByText("Mark unread").click();

    // Switch away and back to re-open the channel
    await page.getByTestId("channel-random").click();
    await expect(page.getByTestId("chat-title")).toHaveText("random");

    // Forced channel unread uses channel-name emphasis, not the thread dot.
    await expect(page.getByTestId("channel-general")).toHaveCSS(
      "font-weight",
      "700",
    );
    await expect(page.getByTestId("channel-unread-dot-general")).toHaveCount(0);

    await page.getByTestId("channel-general").click();
    await expect(page.getByTestId("chat-title")).toHaveText("general");

    // Pill and divider should NOT appear (suppressed for forced-unread)
    await expect(page.getByTestId("message-unread-pill")).toHaveCount(0);
    await expect(page.getByTestId("message-unread-divider")).toHaveCount(0);
  });

  test("05-open-jumps-to-oldest-unread", async ({ page }) => {
    await installMockBridge(page);
    await page.goto("/");

    await page.getByTestId("channel-general").click();
    await expect(page.getByTestId("chat-title")).toHaveText("general");
    await waitForMockLiveSubscription(page, "general");

    await page.getByTestId("channel-random").click();
    await expect(page.getByTestId("chat-title")).toHaveText("random");

    await emitUnreadMessages(page, 20);

    await page.getByTestId("channel-general").click();
    await expect(page.getByTestId("chat-title")).toHaveText("general");

    const oldestUnread = page.getByText("Unread message 1", { exact: true });
    await expect(oldestUnread).toBeInViewport();
    await expect(
      page
        .locator("[class*=route-target-highlight-fade]")
        .filter({ has: oldestUnread }),
    ).toHaveCount(1);
    await expect(page.getByTestId("message-unread-divider")).toBeInViewport();
    await expect(page.getByTestId("message-unread-pill")).toHaveCount(0);

    const { scrollTop, maxScrollTop } = await page
      .getByTestId("message-timeline")
      .evaluate((el) => ({
        scrollTop: el.scrollTop,
        maxScrollTop: el.scrollHeight - el.clientHeight,
      }));
    expect(scrollTop).toBeLessThan(maxScrollTop - 32);
  });

  test("06-cached-channel-jumps-after-newest-window-refresh", async ({
    page,
  }) => {
    await installMockBridge(page);
    await page.goto("/");

    await page.getByTestId("channel-deep-history").click();
    await expect(page.getByTestId("chat-title")).toHaveText("deep-history");
    await waitForMockLiveSubscription(page, "deep-history");

    await page.getByTestId("channel-general").click();
    await expect(page.getByTestId("chat-title")).toHaveText("general");

    const base = unreadTimestamp();
    for (let index = 0; index < 30; index += 1) {
      await emitMockMessage(
        page,
        "deep-history",
        `Away message ${index + 1}`,
        base + index,
      );
    }

    await page.getByTestId("channel-deep-history").click();
    await expect(page.getByTestId("chat-title")).toHaveText("deep-history");

    const oldestUnread = page.getByText("Away message 1", { exact: true });
    await expect(oldestUnread).toBeInViewport();
    await expect(
      page
        .locator("[class*=route-target-highlight-fade]")
        .filter({ has: oldestUnread }),
    ).toHaveCount(1);
    // The newest-window refresh after opening replaces the cached window;
    // the oldest unread must still be on screen once it has landed.
    await page.waitForTimeout(1_500);
    await expect(oldestUnread).toBeInViewport();
    await expect(page.getByTestId("message-unread-divider")).toBeInViewport();
    await expect(page.getByTestId("message-unread-pill")).toHaveCount(0);
  });

  test("07-tall-oldest-unread-releases-scroll", async ({ page }) => {
    await installMockBridge(page);
    await page.goto("/");

    await page.getByTestId("channel-general").click();
    await expect(page.getByTestId("chat-title")).toHaveText("general");
    await waitForMockLiveSubscription(page, "general");

    await page.getByTestId("channel-random").click();
    await expect(page.getByTestId("chat-title")).toHaveText("random");

    const base = unreadTimestamp();
    const alerts = Array.from(
      { length: 60 },
      (_, index) =>
        `- Alert ${index + 1}\n  - Summary: disk usage high\n  - Severity: warning`,
    ).join("\n");
    await emitMockMessage(page, "general", `Tall alert\n\n${alerts}`, base);
    for (let index = 0; index < 5; index += 1) {
      await emitMockMessage(
        page,
        "general",
        `After alert ${index + 1}`,
        base + index + 1,
      );
    }

    await page.getByTestId("channel-general").click();
    await expect(page.getByTestId("chat-title")).toHaveText("general");

    const timeline = page.getByTestId("message-timeline");
    const tallRow = page
      .locator("[data-message-id]")
      .filter({ has: page.getByText("Tall alert", { exact: true }) });
    await expect(tallRow).toBeInViewport();
    const { rowHeight, viewportHeight } = await tallRow.evaluate((row) => ({
      rowHeight: row.getBoundingClientRect().height,
      viewportHeight:
        row.closest<HTMLElement>('[data-testid="message-timeline"]')
          ?.clientHeight ?? 0,
    }));
    expect(rowHeight).toBeGreaterThan(viewportHeight);
    await expect(
      page.locator("[class*=route-target-highlight-fade]").filter({
        has: page.getByText("Tall alert", { exact: true }),
      }),
    ).toHaveCount(1);
    await page.waitForTimeout(500);

    const latest = page.getByTestId("message-scroll-to-latest");
    await expect(latest).toBeVisible();
    await latest.click();
    await page.waitForTimeout(1_000);
    const distanceFromBottom = await timeline.evaluate(
      (el) => el.scrollHeight - el.clientHeight - el.scrollTop,
    );
    expect(distanceFromBottom).toBeLessThanOrEqual(32);
    await expect(
      page.getByText("After alert 5", { exact: true }),
    ).toBeInViewport();

    await timeline.hover();
    await page.mouse.wheel(0, -600);
    await page.waitForTimeout(1_000);
    const afterWheel = await timeline.evaluate(
      (el) => el.scrollHeight - el.clientHeight - el.scrollTop,
    );
    expect(afterWheel).toBeGreaterThan(300);
  });

  test("08-thread-only-unread-opens-oldest-reply", async ({ page }) => {
    await installMockBridge(page);
    await page.goto("/");
    const { rootAId } = await seedUnreadThreadReplies(page);

    await page.getByTestId("channel-general").click();
    await expect(page.getByTestId("chat-title")).toHaveText("general");

    await expect(page).toHaveURL(new RegExp(`thread(RootId)?=${rootAId}`));
    const threadPanel = page.getByTestId("message-thread-panel");
    await expect(threadPanel).toBeVisible();
    await expect(threadPanel).toContainText("Thread root A");
    await expect(
      threadPanel.getByText("Oldest thread reply", { exact: true }),
    ).toBeInViewport();
    await expect(threadPanel.getByText("Newer thread reply")).toHaveCount(0);
  });

  test("09-top-level-unread-wins-over-thread-reply", async ({ page }) => {
    await installMockBridge(page);
    await page.goto("/");
    const { base } = await seedUnreadThreadReplies(page);
    await emitMockEvent(page, {
      content: "Top-level unread",
      createdAt: base + 2,
      pubkey: TEST_IDENTITIES.alice.pubkey,
    });
    await expect(page.getByTestId("channel-general")).toHaveCSS(
      "font-weight",
      "700",
    );

    await page.getByTestId("channel-general").click();
    await expect(page.getByTestId("chat-title")).toHaveText("general");

    const topLevel = page
      .getByTestId("message-timeline")
      .getByText("Top-level unread", { exact: true });
    await expect(topLevel).toBeInViewport();
    await expect(page.getByTestId("message-unread-divider")).toBeInViewport();
    await expect(page).not.toHaveURL(/threadRootId=/);
    await expect(page.getByTestId("message-thread-panel")).toHaveCount(0);
  });
});
