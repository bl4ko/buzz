import assert from "node:assert/strict";
import test from "node:test";

import { composerSeed, selectionSeed } from "./askSeed.ts";

function render(html) {
  document.body.innerHTML = html;
  return document.body;
}

function select(node) {
  const selection = window.getSelection();
  const range = document.createRange();
  range.selectNodeContents(node);
  selection.removeAllRanges();
  selection.addRange(range);
  return selection;
}

test("a selection in a message quotes it with a link", () => {
  render('<div data-message-id="m1"><p id="t">disk is full</p></div>');
  const seed = selectionSeed(select(document.getElementById("t")), "chan");
  assert.deepEqual(seed, {
    quote: "disk is full",
    link: "buzz://message?channel=chan&id=m1",
  });
});

test("no channel gives a quote without a link", () => {
  render('<div data-message-id="m1"><p id="t">x</p></div>');
  assert.equal(
    selectionSeed(select(document.getElementById("t")), null).link,
    null,
  );
});

test("selections outside messages or in an editor are ignored", () => {
  render(
    '<p id="out">topic</p><div data-message-id="m"><div contenteditable="true"><p id="ed">e</p></div></div>',
  );
  assert.equal(
    selectionSeed(select(document.getElementById("out")), "c"),
    null,
  );
  assert.equal(selectionSeed(select(document.getElementById("ed")), "c"), null);
  window.getSelection().removeAllRanges();
  assert.equal(selectionSeed(window.getSelection(), "c"), null);
  assert.equal(selectionSeed(null, "c"), null);
});

test("composer text is quoted, the focused composer wins", () => {
  render(
    '<div data-testid="message-input">first</div><div data-testid="message-input" tabindex="0" id="b"><p>second</p></div>',
  );
  document.getElementById("b").focus();
  assert.deepEqual(composerSeed(document), { quote: "second" });
  document.getElementById("b").blur();
  assert.deepEqual(composerSeed(document), { quote: "first" });
});

test("an empty composer gives no seed", () => {
  render('<div data-testid="message-input"><p><br></p></div>');
  assert.equal(composerSeed(document), null);
  render("<div></div>");
  assert.equal(composerSeed(document), null);
});
