import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const css = readFileSync(new URL("./olympus.css", import.meta.url), "utf8");
const layer = css.match(/@layer components \{([\s\S]*?)\n\}/)?.[1] ?? "";

test("onboarding steps take the Olympus marble, star, and gold colors", () => {
  assert.match(layer, /--buzz-welcome-chartreuse:\s*var\(--olympus-marble\);/);
  assert.match(layer, /--buzz-onboarding-shell-bottom:\s*#eef2ff;/);
  assert.match(layer, /--buzz-onboarding-backup-ink:\s*#8a4b06;/);
  assert.match(
    layer,
    /\.buzz-onboarding-neutral-theme:not\(\.buzz-onboarding-security-theme\)/,
  );
  for (const buzz of [
    /#d7d72e/i,
    /#d7e7f6/i,
    /#717106/i,
    /240 240 205/,
    /113 113 6/,
  ]) {
    assert.doesNotMatch(layer, buzz);
  }
});

test("dark onboarding dialogs drop the olive accents", () => {
  const dark = layer.match(
    /\.dark \.buzz-onboarding-neutral-theme:not\(\.buzz-startup-shell\),[\s\S]*?\{([\s\S]*?)\}/,
  )?.[1];
  assert.ok(dark, "missing dark onboarding override");
  assert.match(dark, /--buzz-onboarding-avatar-accent-bg:\s*247 194 52;/);
  assert.match(dark, /--buzz-onboarding-avatar-action-bg:\s*138 75 6;/);
});
