import assert from "node:assert/strict";
import test from "node:test";

import { createThemeVars, luminance } from "./adaptive-theme.ts";
import {
  SYNTAX_THEMES,
  extractThemeInfo,
  loadThemeData,
} from "./theme-loader.ts";

function hslToHex(value) {
  const [h, s, l] = value.split(" ").map(Number.parseFloat);
  const saturation = s / 100;
  const lightness = l / 100;
  const a = saturation * Math.min(lightness, 1 - lightness);
  const channel = (n) => {
    const k = (n + h / 30) % 12;
    return Math.round(
      255 * (lightness - a * Math.max(-1, Math.min(k - 3, 9 - k, 1))),
    )
      .toString(16)
      .padStart(2, "0");
  };
  return `#${channel(0)}${channel(8)}${channel(4)}`;
}

function contrast(a, b) {
  const first = luminance(a);
  const second = luminance(b);
  return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05);
}

test("destructive controls stay readable in every bundled theme", async () => {
  assert.ok(SYNTAX_THEMES.length > 0);
  for (const name of SYNTAX_THEMES) {
    const info = extractThemeInfo(name, await loadThemeData(name));
    const { isDark, vars } = createThemeVars(info.bg, info.fg, info.comment, {
      added: info.added,
      deleted: info.deleted,
      modified: info.modified,
    });
    const destructive = hslToHex(vars["--destructive"]);
    for (const surface of ["--background", "--popover", "--muted"]) {
      assert.ok(
        contrast(destructive, hslToHex(vars[surface])) >= 4.5,
        `${name}: destructive text must contrast with ${surface}`,
      );
    }
    assert.ok(
      contrast(destructive, hslToHex(vars["--destructive-foreground"])) >= 4.5,
      `${name}: destructive buttons must have readable labels`,
    );
    assert.equal(
      vars["--status-deleted"],
      info.deleted ?? (isDark ? "#f85149" : "#cf222e"),
    );
  }
});

test("Storm separates readable message colors from the button accent", async () => {
  const info = extractThemeInfo(
    "tokyo-night-storm",
    await loadThemeData("tokyo-night-storm"),
  );
  const { vars } = createThemeVars(
    info.bg,
    info.fg,
    info.comment,
    undefined,
    info.name,
  );
  const roles = [
    "--foreground",
    "--muted-foreground",
    "--message-heading-foreground",
    "--message-strong-foreground",
    "--message-code-foreground",
    "--message-link-foreground",
    "--message-author-foreground",
  ];
  for (const role of roles) {
    for (const surface of ["--background", "--popover", "--muted"]) {
      assert.ok(
        contrast(hslToHex(vars[role]), hslToHex(vars[surface])) >= 4.5,
        `${role} must remain readable on ${surface}`,
      );
    }
  }
  assert.notEqual(vars["--message-heading-foreground"], vars["--foreground"]);
  assert.notEqual(vars["--message-strong-foreground"], vars["--foreground"]);
  assert.notEqual(vars["--message-code-foreground"], vars["--foreground"]);
  assert.equal(info.fg, "#a9b1d6");
  assert.equal(info.comment, "#5f6996");
  const other = createThemeVars(info.bg, info.fg, info.comment);
  assert.notEqual(other.vars["--foreground"], vars["--foreground"]);
});
