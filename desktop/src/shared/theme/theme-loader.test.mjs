import assert from "node:assert/strict";
import test from "node:test";
import { createHighlighter } from "shiki";
import { extractThemeInfo, loadThemeData } from "./theme-loader.ts";

test("Tokyo Night Storm loads for the app, terminal, and code blocks", async () => {
  const theme = await loadThemeData("tokyo-night-storm");
  const info = extractThemeInfo("tokyo-night-storm", theme);
  assert.equal(info.bg, "#24283b");
  assert.equal(info.fg, "#a9b1d6");
  assert.equal(info.comment, "#5f6996");
  assert.equal(info.terminalPalette.background, "#24283b");

  const highlighter = await createHighlighter({
    themes: [theme],
    langs: ["javascript"],
  });
  try {
    const result = highlighter.codeToTokens("// Storm", {
      lang: "javascript",
      theme: "tokyo-night-storm",
    });
    assert.equal(result.bg, "#24283b");
    assert.ok(
      result.tokens[0].every(
        (token) => token.color?.toLowerCase() === "#5f6996",
      ),
    );
  } finally {
    highlighter.dispose();
  }
});
