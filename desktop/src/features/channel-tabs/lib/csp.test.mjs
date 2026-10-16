import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

test("desktop CSP allows https frames for link tabs only", () => {
  const config = JSON.parse(
    readFileSync(
      new URL("../../../../src-tauri/tauri.conf.json", import.meta.url),
      "utf8",
    ),
  );
  const csp = config.app.security.csp;
  assert.match(csp, /frame-src https:;/);
  assert.match(csp, /frame-ancestors 'none'/);
  assert.doesNotMatch(csp, /frame-src[^;]*http:/);
});
