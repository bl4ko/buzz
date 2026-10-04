import assert from "node:assert/strict";
import test from "node:test";
import { luminance } from "./adaptive-theme.ts";
import { sectionColorIndex, STORM_SECTION_COLORS } from "./section-colors.ts";

test("section colors follow names across ordering and case changes", () => {
  const names = ["Unreads", "Agents", "Alerts", "Channels"];
  const colors = names.map(
    (name) => STORM_SECTION_COLORS[sectionColorIndex(name)],
  );
  assert.equal(new Set(colors).size, names.length);
  assert.deepEqual(colors, ["#7dcfff", "#b4f9f8", "#e0af68", "#7aa2f7"]);
  names.reverse().forEach((name) => {
    assert.equal(
      sectionColorIndex(name),
      sectionColorIndex(` ${name.toUpperCase()} `),
    );
  });
});

test("every Storm section color is readable on Storm navigation", () => {
  for (const color of STORM_SECTION_COLORS) {
    for (const background of ["#24283b", "#1f2335"]) {
      const a = luminance(color);
      const b = luminance(background);
      assert.ok(
        (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05) >= 4.5,
        color,
      );
    }
  }
});
