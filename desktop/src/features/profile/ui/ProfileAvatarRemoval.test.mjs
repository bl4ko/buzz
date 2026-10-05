import assert from "node:assert/strict";
import { after, afterEach, before, test } from "node:test";
import { JSDOM } from "jsdom";

const dom = new JSDOM("<!doctype html><html><body></body></html>", {
  url: "http://localhost",
});
class LoadedImage extends dom.window.EventTarget {
  complete = false;
  set src(value) {
    this.complete = true;
    queueMicrotask(() => this.dispatchEvent(new dom.window.Event("load")));
  }
}
let React;
let act;
let render;
let cleanup;
let ProfileAvatar;
let UserAvatar;
before(async () => {
  Object.assign(globalThis, {
    document: dom.window.document,
    HTMLElement: dom.window.HTMLElement,
    IS_REACT_ACT_ENVIRONMENT: true,
    window: dom.window,
  });
  dom.window.Image = LoadedImage;
  globalThis.Image = LoadedImage;
  React = (await import("react")).default;
  ({ act, render, cleanup } = await import("@testing-library/react"));
  ({ ProfileAvatar } = await import("./ProfileAvatar.tsx"));
  ({ UserAvatar } = await import("@/shared/ui/UserAvatar"));
});
afterEach(() => cleanup());
after(() => dom.window.close());

for (const surface of ["profile", "message"]) {
  test(`${surface} avatar shows initials after removing a loaded icon`, async () => {
    const Component = surface === "profile" ? ProfileAvatar : UserAvatar;
    const props = {
      label: "Icon Test Agent",
      displayName: "Icon Test Agent",
      testId: "avatar",
      fallbackDelayMs: 0,
    };
    let view;
    await act(async () => {
      view = render(
        React.createElement(Component, {
          ...props,
          avatarUrl: "https://example.com/icon.png",
        }),
      );
    });
    assert.ok(view.queryByTestId("avatar-image"));
    await act(async () => {
      view.rerender(
        React.createElement(Component, { ...props, avatarUrl: "" }),
      );
    });
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 10));
    });
    assert.equal(view.queryByTestId("avatar-image"), null);
    assert.ok(view.getByTestId("avatar-fallback").textContent.trim());
  });
}
