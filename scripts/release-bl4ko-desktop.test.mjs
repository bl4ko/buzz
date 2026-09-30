import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { X509Certificate } from "node:crypto";
import {
  copyFileSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import {
  createSigningKeychain,
  releaseConfig,
} from "./release-bl4ko-desktop.mjs";

test("macOS signs without access to the login Keychain", {
  skip: process.platform !== "darwin",
}, () => {
  const temporary = mkdtempSync(path.join(tmpdir(), "buzz-signing-test-"));
  const keychain = path.join(temporary, "test.keychain-db");
  const key = path.join(temporary, "key.pem");
  const certificate = path.join(temporary, "certificate.pem");
  const run = (command, args) =>
    execFileSync(command, args, { stdio: ["ignore", "pipe", "pipe"] });
  try {
    run("openssl", [
      "req",
      "-x509",
      "-newkey",
      "rsa:2048",
      "-nodes",
      "-keyout",
      key,
      "-out",
      certificate,
      "-subj",
      "/CN=Buzz import check",
      "-addext",
      "basicConstraints=critical,CA:FALSE",
      "-addext",
      "keyUsage=critical,digitalSignature",
      "-addext",
      "extendedKeyUsage=codeSigning",
      "-days",
      "1",
    ]);
    createSigningKeychain(
      certificate,
      key,
      path.join(temporary, "signing.p12"),
      keychain,
    );
    assert.ok(
      run("security", ["list-keychains", "-d", "user"])
        .toString()
        .includes(keychain),
      "temporary signing Keychain must be searchable",
    );
    const executable = path.join(temporary, "check");
    copyFileSync("/usr/bin/true", executable);
    const identity = new X509Certificate(
      readFileSync(certificate),
    ).fingerprint.replaceAll(":", "");
    run("codesign", [
      "--force",
      "--keychain",
      keychain,
      "--sign",
      identity,
      executable,
    ]);
    run("codesign", ["--verify", "--strict", executable]);
  } finally {
    try {
      run("security", ["delete-keychain", keychain]);
    } finally {
      rmSync(temporary, { recursive: true, force: true });
    }
  }
});

test("local release disables updates and validates its version", () => {
  const config = releaseConfig("0.5.25-bl4ko.10", "0.5.25");
  assert.equal(config.version, "0.5.25-bl4ko.10");
  assert.equal(config.identifier, "xyz.bl4ko.buzz.custom");
  assert.equal(config.bundle.createUpdaterArtifacts, false);
  assert.deepEqual(config.plugins.updater, { endpoints: [] });
  assert.ok(!Object.hasOwn(config.bundle, "externalBin"));
  for (const invalid of [
    undefined,
    "0.5.25",
    "0.5.25-bl4ko.0",
    "0.5.26-bl4ko.1",
    "0.5.25-bl4ko.1/../bad",
  ]) {
    assert.throws(() => releaseConfig(invalid, "0.5.25"));
  }
  assert.throws(
    () =>
      execFileSync(
        process.execPath,
        [
          path.join(import.meta.dirname, "release-bl4ko-desktop.mjs"),
          "0.5.25-bl4ko.10",
          "--publish",
        ],
        { stdio: "pipe" },
      ),
    /Use: release-bl4ko-desktop/,
  );
});
