import assert from "node:assert/strict";
import { after, afterEach, before, test } from "node:test";
import { JSDOM } from "jsdom";
const dom = new JSDOM("<!doctype html><html><body></body></html>", {
  url: "http://localhost",
});
before(() =>
  Object.assign(globalThis, {
    document: dom.window.document,
    window: dom.window,
    HTMLElement: dom.window.HTMLElement,
    IS_REACT_ACT_ENVIRONMENT: true,
  }),
);
afterEach(async () => (await import("@testing-library/react")).cleanup());
after(() => dom.window.close());

test("collapsed coordination row is one actionable button with a plain preview", async () => {
  const { createElement } = await import("react");
  const { render, fireEvent } = await import("@testing-library/react");
  const { AgentCoordinationCollapsedRow } = await import(
    "./AgentCoordinationDisclosure.tsx"
  );
  let expanded = 0;
  const view = render(
    createElement(AgentCoordinationCollapsedRow, {
      author: "Fizz",
      body: "**Done**: see `crates/x`\n\n```rs\nfn a() {}\n```",
      createdAt: 1_700_000_000,
      isAgent: true,
      messageId: "m1",
      onExpand: () => {
        expanded += 1;
      },
    }),
  );
  const button = view.getByRole("button", {
    name: "Agent coordination from Fizz. Show message",
  });
  assert.equal(button.getAttribute("aria-expanded"), "false");
  assert.match(button.textContent ?? "", /Done: see crates\/x \[code\]/);
  fireEvent.click(button);
  assert.equal(expanded, 1);
});

test("coordinationPreview flattens markdown to one line", async () => {
  const { coordinationPreview } = await import(
    "./AgentCoordinationDisclosure.tsx"
  );
  assert.equal(
    coordinationPreview("# Title\n\n- [link](https://x.y) and _em_"),
    "Title - link and em",
  );
});
