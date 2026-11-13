import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import {
  brandAppBundle,
  nextBuild,
  takeCiSecrets,
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

test("Mac bundle keeps the Bl4uzz.app file and shows Olympus", () => {
  const directory = mkdtempSync(path.join(tmpdir(), "bl4uzz-brand-"));
  try {
    const app = path.join(directory, "Bl4uzz.app");
    const plist = path.join(app, "Contents/Info.plist");
    mkdirSync(path.dirname(plist), { recursive: true });
    execFileSync("plutil", ["-create", "xml1", plist]);
    for (const field of ["CFBundleName", "CFBundleDisplayName"])
      execFileSync("plutil", ["-insert", field, "-string", "Buzz", plist]);
    brandAppBundle(app);
    const read = (file) =>
      JSON.parse(execFileSync("plutil", ["-convert", "json", "-o", "-", file]));
    assert.deepEqual(read(plist), {
      CFBundleName: "Olympus",
      CFBundleDisplayName: "Bl4uzz",
      LSHasLocalizedDisplayName: true,
    });
    assert.deepEqual(
      read(path.join(app, "Contents/Resources/en.lproj/InfoPlist.strings")),
      { CFBundleName: "Olympus", CFBundleDisplayName: "Olympus" },
    );
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("Mac build number stays above the uploaded builds", () => {
  assert.equal(nextBuild("next", ["44", "45", "9"]), "46");
  assert.equal(nextBuild("next", []), "1");
  assert.equal(nextBuild("50", ["45"]), "50");
  assert.throws(() => nextBuild("45", ["45"]), /not above/);
  assert.throws(() => nextBuild("1;echo", ["45"]));
});

test("CI signing secrets leave the environment of child processes", () => {
  const env = {
    ASC_API_KEY_ID: "key",
    ASC_API_PRIVATE_KEY: "api-private",
    MAC_APP_CERTIFICATE_ID: "cert-id",
    MAC_INSTALLER_PRIVATE_KEY: "installer-private",
    PATH: "/usr/bin",
  };
  const secrets = takeCiSecrets(env);
  assert.deepEqual(env, { PATH: "/usr/bin" });
  assert.deepEqual(secrets["api-keys/appstoreconnect"], {
    "key-id": "key",
    "private-key": "api-private",
  });
  assert.equal(
    secrets["signing/mac-app-distribution"]["certificate-id"],
    "cert-id",
  );
  assert.equal(
    secrets["signing/mac-installer-distribution"]["private-key"],
    "installer-private",
  );
});
