import assert from "node:assert/strict";
import test from "node:test";

import {
  olympusCanDelete,
  olympusFieldLocked,
  olympusLockedPaths,
} from "./olympusOwnership.ts";

test("an old operator locks every field of a gitops object", () => {
  const legacy = { managedBy: "gitops", gitopsFields: null };
  assert.equal(olympusFieldLocked(legacy, "spec.suspend"), true);
  assert.equal(
    olympusFieldLocked({ managedBy: null, gitopsFields: null }, "spec.suspend"),
    false,
  );
});

test("only git-owned fields and their parents or children are locked", () => {
  const zeus = {
    managedBy: "gitops",
    gitopsFields: ["spec.model", "spec.profile.displayName", "spec.mcpServers"],
  };
  assert.equal(olympusFieldLocked(zeus, "spec.suspend"), false);
  assert.equal(olympusFieldLocked(zeus, "spec.egress"), false);
  assert.equal(olympusFieldLocked(zeus, "spec.model"), true);
  assert.equal(olympusFieldLocked(zeus, "spec.profile"), true);
  assert.equal(olympusFieldLocked(zeus, "spec.profile.about"), false);
  assert.equal(olympusFieldLocked(zeus, "spec.mcpServers.tools"), true);
  assert.equal(olympusFieldLocked(zeus, "spec.modelX"), false);
  assert.deepEqual(
    olympusLockedPaths(zeus, { suspend: true, model: "x", egress: [] }),
    ["spec.model"],
  );
  assert.equal(olympusCanDelete(zeus), false);
  assert.equal(olympusCanDelete({ managedBy: null, gitopsFields: [] }), true);
});
