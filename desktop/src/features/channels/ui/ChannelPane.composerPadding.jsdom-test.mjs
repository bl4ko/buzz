import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import * as React from "react";
import { act } from "react";
import { createRoot } from "react-dom/client";

import { useComposerHeightPadding } from "../../messages/ui/useComposerHeightPadding.ts";
import { getMainComposerPaddingKey } from "./ChannelPane.helpers.ts";

const COMPOSER_HEIGHT = 126;
const observed = new Map();

class FakeResizeObserver {
  constructor(callback) {
    this.callback = callback;
  }
  observe(element) {
    observed.set(element, this);
  }
  disconnect() {
    for (const [element, observer] of observed) {
      if (observer === this) observed.delete(element);
    }
  }
}

function deliverResizes() {
  for (const [element, observer] of observed) {
    const blockSize = element.isConnected ? COMPOSER_HEIGHT : 0;
    observer.callback([{ borderBoxSize: [{ blockSize }] }]);
  }
}

function Pane({ hasTabPanel }) {
  const scrollRef = React.useRef(null);
  const composerRef = React.useRef(null);
  useComposerHeightPadding(
    scrollRef,
    composerRef,
    getMainComposerPaddingKey({
      activeChannelId: "c1",
      hasMainComposerOverlay: true,
      hasTabPanel,
      isSinglePanelView: false,
    }),
    "css-variable",
  );
  return React.createElement(
    "div",
    { "data-testid": "timeline-host" },
    React.createElement("div", { ref: scrollRef }),
    hasTabPanel
      ? null
      : React.createElement("div", {
          ref: (el) => {
            composerRef.current = el;
            if (el) {
              el.getBoundingClientRect = () => ({ height: COMPOSER_HEIGHT });
            }
          },
        }),
  );
}

let root;
let container;
const originalResizeObserver = globalThis.ResizeObserver;
const originalRaf = globalThis.requestAnimationFrame;
const originalCancelRaf = globalThis.cancelAnimationFrame;

afterEach(async () => {
  await act(async () => root.unmount());
  container.remove();
  observed.clear();
  globalThis.ResizeObserver = originalResizeObserver;
  globalThis.requestAnimationFrame = originalRaf;
  globalThis.cancelAnimationFrame = originalCancelRaf;
});

test("composer height is measured again after a tab panel closes", async () => {
  globalThis.ResizeObserver = FakeResizeObserver;
  globalThis.requestAnimationFrame = (callback) => setTimeout(callback, 0);
  globalThis.cancelAnimationFrame = (handle) => clearTimeout(handle);
  container = document.createElement("div");
  document.body.appendChild(container);
  root = createRoot(container);
  const host = () => container.querySelector('[data-testid="timeline-host"]');
  const height = () =>
    host().style.getPropertyValue("--composer-overlay-height");

  await act(async () =>
    root.render(React.createElement(Pane, { hasTabPanel: false })),
  );
  assert.equal(height(), `${COMPOSER_HEIGHT}px`);

  await act(async () =>
    root.render(React.createElement(Pane, { hasTabPanel: true })),
  );
  await act(async () => deliverResizes());

  await act(async () =>
    root.render(React.createElement(Pane, { hasTabPanel: false })),
  );
  await act(async () => deliverResizes());
  assert.equal(height(), `${COMPOSER_HEIGHT}px`);
});
