import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  testflightConfig,
  validateDistributionProfile,
} from "./release-bl4ko-macos-testflight.mjs";

test("Mac distribution profile must authorize the app and signing certificate", () => {
  const certificate = Buffer.from("distribution-certificate");
  const profile = {
    Entitlements: {
      "com.apple.application-identifier": "55S37D9HA7.com.bl4ko.buzz",
      "com.apple.developer.team-identifier": "55S37D9HA7",
    },
    TeamIdentifier: ["55S37D9HA7"],
    ExpirationDate: "2027-10-01T08:37:49Z",
    DeveloperCertificates: [certificate.toString("base64")],
  };
  const now = Date.parse("2026-10-05T00:00:00Z");
  assert.doesNotThrow(() =>
    validateDistributionProfile(profile, certificate, now),
  );
  assert.throws(
    () => validateDistributionProfile(profile, Buffer.from("other"), now),
    /signing certificate/,
  );
  assert.throws(
    () =>
      validateDistributionProfile(
        profile,
        certificate,
        Date.parse("2027-10-02"),
      ),
    /expired/,
  );
  assert.throws(
    () =>
      validateDistributionProfile(
        {
          ...profile,
          Entitlements: {
            ...profile.Entitlements,
            "com.apple.application-identifier": "55S37D9HA7.other",
          },
        },
        certificate,
        now,
      ),
    /identity mismatch/,
  );
  assert.throws(
    () =>
      validateDistributionProfile(
        { ...profile, ProvisionedDevices: ["device"] },
        certificate,
        now,
      ),
    /distribution profile/,
  );
});

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
  assert.equal(config.identifier, "com.bl4ko.buzz");
  assert.equal(config.productName, "Bl4uzz");
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
  assert.match(entitlements, /<string>55S37D9HA7\.com\.bl4ko\.buzz<\/string>/);
  assert.doesNotMatch(
    entitlements,
    /disable-library-validation|temporary-exception/,
  );
});
