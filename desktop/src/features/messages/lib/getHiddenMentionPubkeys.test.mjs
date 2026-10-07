import assert from "node:assert/strict";
import test from "node:test";

import { getHiddenMentionPubkeys } from "./getHiddenMentionPubkeys.ts";

const ZEUS = "a".repeat(64);
const ARGUS = "b".repeat(64);
const ATHENE = "c".repeat(64);
const names = { zeus: ZEUS, argus: ARGUS, athene: ATHENE };

test("lists a p-tagged recipient that the body does not mention", () => {
  assert.deepEqual(
    getHiddenMentionPubkeys(
      "Argus: please supply fresh evidence",
      [
        ["p", ARGUS],
        ["p", ATHENE],
      ],
      [],
      names,
    ),
    [ARGUS, ATHENE],
  );
});

test("omits inline mentions, the sender, and address-prefix chips", () => {
  assert.deepEqual(
    getHiddenMentionPubkeys(
      "@Zeus please review",
      [
        ["p", ZEUS],
        ["p", ATHENE],
        ["p", ARGUS.toUpperCase()],
      ],
      [ATHENE, ARGUS],
      names,
    ),
    [],
  );
});

test("ignores non-notifying mention references and duplicates", () => {
  assert.deepEqual(
    getHiddenMentionPubkeys(
      "status update",
      [
        ["mention", ZEUS],
        ["p", ARGUS],
        ["p", ARGUS],
        ["p", ""],
      ],
      [],
      undefined,
    ),
    [ARGUS],
  );
});
