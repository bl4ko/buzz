import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { testflightConfig } from "./release-bl4ko-macos-testflight.mjs";

test("Mac TestFlight build uses the sandbox and numeric Apple build number", () => {
  assert.equal(testflightConfig("4").bundle.macOS.bundleVersion, "4");
  for (const build of [
    undefined,
    "0",
    "-1",
    "4.1",
    "4-bl4ko",
    "1;echo",
    "1234567890123456789",
  ])
    assert.throws(() => testflightConfig(build));
  const config = JSON.parse(
    readFileSync(
      new URL("../desktop/src-tauri/tauri.appstore.conf.json", import.meta.url),
    ),
  );
  assert.equal(config.app.macOSPrivateApi, false);
  assert.equal(config.identifier, "xyz.bl4ko.buzz.custom");
  const entitlements = readFileSync(
    new URL(
      `../desktop/src-tauri/${config.bundle.macOS.entitlements}`,
      import.meta.url,
    ),
    "utf8",
  );
  assert.match(
    entitlements,
    /<key>com.apple.security.app-sandbox<\/key>\s*<true\/>/,
  );
  assert.doesNotMatch(
    entitlements,
    /disable-library-validation|temporary-exception/,
  );
});
