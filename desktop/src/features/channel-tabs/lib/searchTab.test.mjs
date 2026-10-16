import assert from "node:assert/strict";
import { test } from "node:test";

import { authorOnlyFilter, resolveSearchTab } from "./searchTab.ts";

const ATHENE = "3c".padEnd(64, "0");
const members = [{ pubkey: ATHENE, displayName: "Athene" }];

test("from: resolves a member name to an author filter", () => {
  const result = resolveSearchTab("from:Athene CVE", members);
  assert.equal(result.text.trim(), "CVE");
  assert.deepEqual(result.authors, [ATHENE]);
  assert.equal(result.unresolved, null);
  assert.deepEqual(resolveSearchTab("from:@athene CVE", members).authors, [
    ATHENE,
  ]);
});

test("unknown names are reported and plain text passes through", () => {
  assert.equal(
    resolveSearchTab("from:Nobody CVE", members).unresolved,
    "Nobody",
  );
  const plain = resolveSearchTab("CVE", members);
  assert.equal(plain.authors, undefined);
  assert.equal(plain.text.trim(), "CVE");
});

test("a from-only search becomes an author filter on the channel", () => {
  const search = resolveSearchTab("from:Athene", members);
  assert.equal(search.text.trim(), "");
  assert.deepEqual(authorOnlyFilter(search, "c1"), {
    kinds: [9, 40002],
    "#h": ["c1"],
    authors: [ATHENE],
    limit: 50,
  });
  assert.equal(
    authorOnlyFilter(resolveSearchTab("from:Athene CVE", members), "c1"),
    null,
  );
  assert.equal(authorOnlyFilter(resolveSearchTab("CVE", members), "c1"), null);
});
