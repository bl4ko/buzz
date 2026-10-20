import assert from "node:assert/strict";
import { afterEach, beforeEach, test } from "node:test";

import * as React from "react";
import { act } from "react";
import { createRoot } from "react-dom/client";

import { MessageFold } from "./MessageFold.tsx";
import { resetMessageFoldState } from "./messageFoldState.ts";

const LINE_HEIGHT = 20;
let root;
let container;
let observers;
let restore;

beforeEach(() => {
  observers = [];
  const originalResizeObserver = globalThis.ResizeObserver;
  const originalGetComputedStyle = window.getComputedStyle;
  const offsetHeight = Object.getOwnPropertyDescriptor(
    window.HTMLElement.prototype,
    "offsetHeight",
  );
  globalThis.ResizeObserver = class {
    constructor(callback) {
      this.callback = callback;
      observers.push(this);
    }
    observe() {}
    disconnect() {
      observers = observers.filter((observer) => observer !== this);
    }
  };
  window.getComputedStyle = (element) => {
    originalGetComputedStyle(element);
    return { fontSize: "16px", lineHeight: `${LINE_HEIGHT}px` };
  };
  Object.defineProperty(window.HTMLElement.prototype, "offsetHeight", {
    configurable: true,
    get() {
      const measured =
        this.dataset.naturalHeight ??
        this.querySelector("[data-natural-height]")?.dataset.naturalHeight;
      return Number(measured ?? 0);
    },
  });
  restore = () => {
    globalThis.ResizeObserver = originalResizeObserver;
    window.getComputedStyle = originalGetComputedStyle;
    if (offsetHeight) {
      Object.defineProperty(
        window.HTMLElement.prototype,
        "offsetHeight",
        offsetHeight,
      );
    } else {
      delete window.HTMLElement.prototype.offsetHeight;
    }
  };
});

afterEach(async () => {
  await act(async () => root.unmount());
  container.remove();
  restore();
  resetMessageFoldState();
});

function Body({ height, children }) {
  return React.createElement(
    "div",
    { "data-natural-height": String(height) },
    children ?? "Long agent reply",
  );
}

async function render(height, props = {}, children) {
  container = document.createElement("div");
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () =>
    root.render(
      React.createElement(
        MessageFold,
        props,
        React.createElement(Body, { height }, children),
      ),
    ),
  );
}

function setContentHeight(height) {
  container
    .querySelector("[data-natural-height]")
    .setAttribute("data-natural-height", String(height));
}

const toggle = () =>
  container.querySelector('[data-testid="message-fold-toggle"]');
const clip = () => container.querySelector('[data-testid="message-fold-clip"]');

test("a short body has no toggle and no clip", async () => {
  await render(LINE_HEIGHT * 3);
  assert.equal(toggle(), null);
  assert.equal(clip().style.maxHeight, "");
});

test("a long body folds to eight lines and toggles with the button", async () => {
  await render(LINE_HEIGHT * 30);
  const button = toggle();
  assert.ok(button);
  assert.equal(button.tagName, "BUTTON");
  assert.equal(button.type, "button");
  assert.equal(button.textContent, "Show more");
  assert.equal(button.getAttribute("aria-expanded"), "false");
  assert.equal(button.getAttribute("aria-controls"), clip().id);
  assert.equal(clip().style.maxHeight, `${LINE_HEIGHT * 8}px`);
  assert.equal(clip().style.overflow, "hidden");

  await act(async () => button.click());
  assert.equal(toggle().textContent, "Show less");
  assert.equal(toggle().getAttribute("aria-expanded"), "true");
  assert.equal(clip().style.maxHeight, "");

  await act(async () => toggle().click());
  assert.equal(toggle().textContent, "Show more");
  assert.equal(clip().style.maxHeight, `${LINE_HEIGHT * 8}px`);
});

test("a body that grows past the limit gains the fold on resize", async () => {
  await render(LINE_HEIGHT * 2);
  assert.equal(toggle(), null);
  setContentHeight(LINE_HEIGHT * 12);
  await act(async () => {
    for (const observer of observers) observer.callback([]);
  });
  assert.equal(toggle().textContent, "Show more");
});

test("a jump target starts expanded with Show less", async () => {
  await render(LINE_HEIGHT * 30, { forceExpanded: true });
  assert.equal(toggle().textContent, "Show less");
  assert.equal(clip().style.maxHeight, "");
});

test("a body with media is not folded", async () => {
  await render(
    LINE_HEIGHT * 30,
    {},
    React.createElement("img", { alt: "", src: "https://example.com/a.png" }),
  );
  assert.equal(toggle(), null);
  assert.equal(clip().style.maxHeight, "");
});

test("an expanded message stays expanded after the row remounts", async () => {
  await render(LINE_HEIGHT * 30, { foldId: "message-1" });
  await act(async () => toggle().click());
  await act(async () => root.unmount());
  container.remove();

  await render(LINE_HEIGHT * 30, { foldId: "message-1" });
  assert.equal(toggle().textContent, "Show less");
  assert.equal(clip().style.maxHeight, "");
});

test("a jump target stays expanded after the highlight ends", async () => {
  await render(LINE_HEIGHT * 30, { foldId: "message-2", forceExpanded: true });
  await act(async () => root.unmount());
  container.remove();

  await render(LINE_HEIGHT * 30, { foldId: "message-2" });
  assert.equal(toggle().textContent, "Show less");
});
