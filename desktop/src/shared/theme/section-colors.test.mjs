import assert from "node:assert/strict";
import test from "node:test";
import { luminance } from "./adaptive-theme.ts";
import {
  sectionForeground,
  STORM_SECTION_FOREGROUND,
} from "./section-colors.ts";

test("sections share one fixed foreground role", () => {
  assert.equal(
    sectionForeground(),
    "var(--sidebar-section-foreground, currentColor)",
  );
  assert.equal(STORM_SECTION_FOREGROUND, "#7aa2f7");
});

test("Storm section foreground is readable on navigation", () => {
  for (const background of ["#24283b", "#1f2335"]) {
    const a = luminance(STORM_SECTION_FOREGROUND);
    const b = luminance(background);
    assert.ok((Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05) >= 4.5);
  }
});
