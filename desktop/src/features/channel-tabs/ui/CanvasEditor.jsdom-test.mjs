import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import * as React from "react";
import { act } from "react";
import { createRoot } from "react-dom/client";

import { CanvasEditor } from "./CanvasEditor.tsx";

let root;
let container;
let calls;

async function render(props) {
  calls = [];
  container = document.createElement("div");
  document.body.appendChild(container);
  root = createRoot(container);
  const handler = (name) => () => calls.push(name);
  await act(async () =>
    root.render(
      React.createElement(CanvasEditor, {
        draft: "# Notes",
        onDraftChange: () => {},
        conflictAuthor: null,
        saving: false,
        onSave: handler("save"),
        onReload: handler("reload"),
        onOverwrite: handler("overwrite"),
        onCancel: handler("cancel"),
        ...props,
      }),
    ),
  );
}

afterEach(async () => {
  await act(async () => root.unmount());
  container.remove();
});

const q = (id) => container.querySelector(`[data-testid="${id}"]`);

test("conflict banner offers reload or overwrite and blocks plain save", async () => {
  await render({ conflictAuthor: "Athene" });
  assert.equal(
    q("canvas-conflict").textContent.includes(
      "Changed by Athene. Reload or overwrite?",
    ),
    true,
  );
  assert.equal(q("canvas-save").disabled, true);
  await act(async () => q("canvas-reload").click());
  await act(async () => q("canvas-overwrite").click());
  assert.deepEqual(calls, ["reload", "overwrite"]);
});

test("oversize drafts cannot be saved", async () => {
  await render({ draft: "x".repeat(65_537) });
  assert.equal(q("canvas-save").disabled, true);
  assert.match(q("canvas-size").textContent, /65537 \/ 65536/);
});

test("a clean draft saves", async () => {
  await render({});
  await act(async () => q("canvas-save").click());
  assert.deepEqual(calls, ["save"]);
});
