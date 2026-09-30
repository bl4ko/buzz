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
  advancesVersion,
  createSigningKeychain,
  releaseInfo,
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

test("custom release uses the fork updater and prevents version rollback", () => {
  const info = releaseInfo("0.5.25-bl4ko.10", "0.5.25");
  assert.equal(info.tag, "custom-desktop-v0.5.25-bl4ko.10");
  assert.equal(
    info.endpoint,
    "https://github.com/bl4ko/buzz/releases/download/buzz-custom-desktop-latest/latest.json",
  );
  assert.equal(
    info.url,
    `https://github.com/bl4ko/buzz/releases/download/${info.tag}/${info.archive}`,
  );
  for (const invalid of [
    undefined,
    "0.5.25",
    "0.5.25-bl4ko.0",
    "0.5.26-bl4ko.1",
    "0.5.25-bl4ko.1/../bad",
  ]) {
    assert.throws(() => releaseInfo(invalid, "0.5.25"));
  }
  assert.ok(advancesVersion(info.version, "0.5.25-bl4ko.9"));
  assert.ok(advancesVersion("0.5.26-bl4ko.1", info.version));
  assert.ok(advancesVersion("0.6.0-bl4ko.1", "0.5.99-bl4ko.99"));
  assert.ok(!advancesVersion(info.version, info.version));
  assert.ok(!advancesVersion("0.5.25-bl4ko.9", info.version));
  assert.ok(!advancesVersion(info.version, "0.5.26-bl4ko.1"));
  assert.throws(() => advancesVersion(info.version, "bad"));
  const temporary = mkdtempSync(path.join(tmpdir(), "buzz-release-check-"));
  try {
    const signature = path.join(temporary, "app.sig");
    writeFileSync(signature, "signed-archive");
    const manifest = JSON.parse(
      execFileSync(
        "bash",
        [
          "desktop/scripts/generate-oss-latest-json.sh",
          info.version,
          `darwin-aarch64:${signature}:${info.url}`,
        ],
        { cwd: path.resolve(import.meta.dirname, "..") },
      ),
    );
    assert.equal(manifest.version, info.version);
    assert.deepEqual(manifest.platforms, {
      "darwin-aarch64": { signature: "signed-archive", url: info.url },
    });
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
});
