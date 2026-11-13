import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const usage = readFileSync(
  new URL("./OlympusUsagePanel.tsx", import.meta.url),
  "utf8",
);
const agents = readFileSync(
  new URL("../../olympus/ui/OlympusAgentsTab.tsx", import.meta.url),
  "utf8",
);

test("the usage table fits its container with no sideways scroll", () => {
  assert.doesNotMatch(usage, /min-w-\[720px\]/);
  assert.doesNotMatch(usage, /overflow-x-auto/);
  assert.match(usage, /"@container overflow-hidden rounded-2xl/);
  assert.match(usage, /const MEDIUM = "hidden @xl:table-cell";/);
  assert.match(usage, /const WIDE = "hidden @3xl:table-cell";/);
  assert.match(usage, /@xl:hidden/);
});

test("agent rows stack by their own width and keep the master badge in flow", () => {
  assert.match(agents, /<li className="@container"/);
  assert.match(agents, /@2xl:grid-cols-\[minmax\(0,1fr\)_13rem_9rem\]/);
  assert.doesNotMatch(agents, /md:grid-cols-\[minmax\(0,1fr\)_13rem_9rem\]/);
  assert.match(agents, /data-testid="olympus-master-chip"/);
});
