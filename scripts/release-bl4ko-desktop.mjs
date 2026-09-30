import { execFileSync } from "node:child_process";
import { randomBytes, X509Certificate } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const desktop = path.join(root, "desktop");
const applePath =
  "envs/external/apple/restricted/signing/developer-id-application";
const versionPattern = /^(\d+\.\d+\.\d+)-bl4ko\.([1-9]\d*)$/;

export function releaseConfig(version, upstreamVersion) {
  const match = versionPattern.exec(version ?? "");
  if (!match || match[1] !== upstreamVersion) {
    throw new Error(
      `Version must be ${upstreamVersion}-bl4ko.N, with N starting at 1`,
    );
  }
  return {
    productName: "Buzz Custom",
    identifier: "xyz.bl4ko.buzz.custom",
    version,
    bundle: {
      createUpdaterArtifacts: false,
      macOS: { minimumSystemVersion: "10.15" },
    },
    plugins: { updater: { endpoints: [] } },
  };
}

function run(command, args, options = {}) {
  return execFileSync(command, args, {
    cwd: root,
    stdio: "inherit",
    ...options,
  });
}

function output(command, args, options = {}) {
  return run(command, args, { stdio: ["ignore", "pipe", "pipe"], ...options })
    .toString()
    .trim();
}

export function createSigningKeychain(certificate, key, bundle, keychain) {
  const password = randomBytes(24).toString("hex");
  try {
    run("security", ["create-keychain", "-p", password, keychain]);
    run("security", ["set-keychain-settings", "-lut", "21600", keychain]);
    run("security", ["unlock-keychain", "-p", password, keychain]);
    run(
      "openssl",
      [
        "pkcs12",
        "-export",
        "-in",
        certificate,
        "-inkey",
        key,
        "-out",
        bundle,
        "-keypbe",
        "PBE-SHA1-3DES",
        "-certpbe",
        "PBE-SHA1-3DES",
        "-macalg",
        "sha1",
        "-passout",
        "env:BUZZ_P12_PASSWORD",
      ],
      { env: { ...process.env, BUZZ_P12_PASSWORD: password } },
    );
    run("security", [
      "import",
      bundle,
      "-k",
      keychain,
      "-P",
      password,
      "-T",
      "/usr/bin/codesign",
    ]);
    run(
      "security",
      [
        "set-key-partition-list",
        "-S",
        "apple-tool:,apple:,codesign:",
        "-s",
        "-k",
        password,
        keychain,
      ],
      { stdio: "ignore" },
    );
    const keychains = output("security", ["list-keychains", "-d", "user"])
      .split("\n")
      .map((item) => item.trim().replace(/^"|"$/g, ""))
      .filter(Boolean);
    run("security", [
      "list-keychains",
      "-d",
      "user",
      "-s",
      ...keychains,
      keychain,
    ]);
  } catch {
    throw new Error("Temporary signing Keychain setup failed");
  }
}

function vaultEnv() {
  const env = { ...process.env, VAULT_ADDR: "https://vault.xqx.uk:8200" };
  delete env.VAULT_TOKEN;
  delete env.TF_VAR_vault_token;
  return env;
}

function secret(name) {
  return JSON.parse(
    output("vault", ["kv", "get", "-format=json", `kv/${name}`], {
      env: vaultEnv(),
    }),
  ).data.data;
}

function notarize(directory, version) {
  const temporary = mkdtempSync(path.join(tmpdir(), "buzz-notary-"));
  try {
    const apple = secret(
      "envs/external/apple/restricted/api-keys/appstoreconnect",
    );
    const key = path.join(temporary, "AuthKey.p8");
    writeFileSync(key, apple["private-key"], { mode: 0o600 });
    const auth = [
      "--key",
      key,
      "--key-id",
      apple["key-id"],
      "--issuer",
      apple["issuer-id"],
    ];
    const app = path.join(directory, "Buzz Custom.app");
    const zip = path.join(directory, `Buzz-Custom_${version}_aarch64.zip`);
    const record = path.join(directory, "notarization.json");
    const submission = existsSync(record)
      ? JSON.parse(readFileSync(record))
      : JSON.parse(
          output("xcrun", [
            "notarytool",
            "submit",
            zip,
            ...auth,
            "--output-format",
            "json",
          ]),
        );
    if (!/^[0-9a-f-]{36}$/i.test(submission.id ?? "")) {
      throw new Error("Apple returned an invalid submission ID");
    }
    writeFileSync(record, `${JSON.stringify(submission, null, 2)}\n`);
    const result = JSON.parse(
      output("xcrun", [
        "notarytool",
        "info",
        submission.id,
        ...auth,
        "--output-format",
        "json",
      ]),
    );
    writeFileSync(record, `${JSON.stringify(result, null, 2)}\n`);
    if (result.status === "In Progress") {
      console.log(
        `Apple review pending: ${submission.id}. Resume with: node scripts/release-bl4ko-desktop.mjs ${version} --resume`,
      );
      return;
    }
    if (result.status !== "Accepted") {
      run("xcrun", [
        "notarytool",
        "log",
        submission.id,
        ...auth,
        path.join(directory, "notarization-log.json"),
      ]);
      throw new Error(`Apple review failed: ${result.status}`);
    }
    run("xcrun", ["stapler", "staple", app]);
    run("xcrun", ["stapler", "validate", app]);
    run("codesign", ["--verify", "--deep", "--strict", app]);
    run("spctl", ["--assess", "--type", "execute", "--verbose=2", app]);
    run("ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", app, zip]);
    console.log(`Ready: ${zip}`);
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
}

async function release(version, mode) {
  const resume = mode === "--resume";
  if (process.platform !== "darwin" || process.arch !== "arm64")
    throw new Error("Build on the Apple silicon Mac mini");
  const upstreamVersion = JSON.parse(
    readFileSync(path.join(desktop, "package.json")),
  ).version;
  if (!versionPattern.test(version ?? ""))
    throw new Error("Use an upstream-version-bl4ko.N build version");
  const config = resume ? undefined : releaseConfig(version, upstreamVersion);
  const releaseDirectory = path.join(
    root,
    "..",
    "buzz-builds",
    "desktop",
    version,
  );
  if (!resume && existsSync(releaseDirectory)) {
    throw new Error(`Local build already exists: ${releaseDirectory}`);
  }
  if (!resume && output("git", ["status", "--porcelain"]))
    throw new Error("Commit the source changes before building");
  const identity = JSON.parse(
    output("vault", ["token", "lookup", "-format=json"], { env: vaultEnv() }),
  ).data;
  if (
    identity.path !== "auth/approle/login" ||
    identity.meta?.role_name !== "mac-mini-temp" ||
    identity.ttl < 3600
  ) {
    throw new Error(
      "Use the mac-mini-temp Vault AppRole token with at least one hour remaining",
    );
  }
  if (resume) {
    if (!existsSync(path.join(releaseDirectory, "notarization.json")))
      throw new Error("No local notarization submission to resume");
    notarize(releaseDirectory, version);
    return;
  }
  const signing = secret(applePath);
  if (!signing.certificate)
    throw new Error(
      "Apple Developer ID certificate is missing. Complete the Account Holder step in FORK.md",
    );
  const temporary = mkdtempSync(path.join(tmpdir(), "buzz-custom-release-"));
  const keychain = path.join(temporary, "signing.keychain-db");
  try {
    const certificate = path.join(temporary, "developer-id.cer");
    const certificatePem = path.join(temporary, "developer-id.pem");
    const key = path.join(temporary, "developer-id.key");
    const keyBundle = path.join(temporary, "developer-id.p12");
    writeFileSync(certificate, Buffer.from(signing.certificate, "base64"), {
      mode: 0o600,
    });
    writeFileSync(key, signing["private-key"], { mode: 0o600 });
    const certificateHash = output("openssl", [
      "x509",
      "-inform",
      "DER",
      "-in",
      certificate,
      "-fingerprint",
      "-sha1",
      "-noout",
    ])
      .split("=")
      .at(-1)
      .replaceAll(":", "");
    run("openssl", [
      "x509",
      "-inform",
      "DER",
      "-in",
      certificate,
      "-out",
      certificatePem,
    ]);
    createSigningKeychain(certificatePem, key, keyBundle, keychain);
    const intermediateResponse = await fetch(
      "https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer",
    );
    if (!intermediateResponse.ok)
      throw new Error(
        `Apple certificate authority download failed: HTTP ${intermediateResponse.status}`,
      );
    const intermediate = Buffer.from(await intermediateResponse.arrayBuffer());
    if (
      !new X509Certificate(readFileSync(certificate)).verify(
        new X509Certificate(intermediate).publicKey,
      )
    )
      throw new Error(
        "Developer ID certificate authority does not match the signing certificate",
      );
    const intermediatePath = path.join(temporary, "developer-id-g2.cer");
    writeFileSync(intermediatePath, intermediate);
    run("security", ["import", intermediatePath, "-k", keychain]);
    if (
      !output("security", [
        "find-identity",
        "-v",
        "-p",
        "codesigning",
        keychain,
      ]).includes(certificateHash)
    )
      throw new Error(
        "Developer ID signing identity is not available in the temporary Keychain",
      );
    const env = { ...process.env };
    delete env.BUZZ_UPDATER_PUBLIC_KEY;
    delete env.BUZZ_UPDATER_ENDPOINT;
    delete env.TAURI_SIGNING_PRIVATE_KEY;
    delete env.TAURI_SIGNING_PRIVATE_KEY_PASSWORD;
    run("pnpm", ["run", "typecheck"], { cwd: desktop });
    run("pnpm", ["run", "check"], { cwd: desktop });
    run(
      "pnpm",
      [
        "exec",
        "node",
        "--import",
        "./test-jsdom-setup.mjs",
        "--import",
        "./test-loader.mjs",
        "--experimental-strip-types",
        "--test-force-exit",
        "--test",
        "src/features/huddle/components/externalAgents.jsdom-test.mjs",
      ],
      { cwd: desktop },
    );
    run("cargo", [
      "build",
      "--locked",
      "--release",
      "-p",
      "buzz-acp",
      "-p",
      "buzz-agent",
      "-p",
      "buzz-backend-kubernetes",
      "-p",
      "buzz-dev-mcp",
      "-p",
      "git-credential-nostr",
      "-p",
      "buzz-cli",
    ]);
    run("bash", ["scripts/bundle-sidecars.sh"]);
    const configPath = path.join(temporary, "tauri.custom.conf.json");
    writeFileSync(configPath, JSON.stringify(config));
    run(
      "pnpm",
      [
        "tauri",
        "build",
        "--bundles",
        "app",
        "--config",
        configPath,
        "--no-sign",
        "--ci",
      ],
      { cwd: desktop, env },
    );
    const app = path.join(
      desktop,
      "src-tauri/target/release/bundle/macos/Buzz Custom.app",
    );
    const plist = path.join(app, "Contents/Info.plist");
    for (const field of ["CFBundleName", "CFBundleDisplayName"])
      run("plutil", ["-replace", field, "-string", "Buzz Custom", plist]);
    const macOS = path.join(app, "Contents/MacOS");
    for (const binary of readdirSync(macOS))
      run("codesign", [
        "--force",
        "--keychain",
        keychain,
        "--sign",
        certificateHash,
        "--options",
        "runtime",
        "--timestamp",
        path.join(macOS, binary),
      ]);
    run("codesign", [
      "--force",
      "--keychain",
      keychain,
      "--sign",
      certificateHash,
      "--options",
      "runtime",
      "--timestamp",
      "--entitlements",
      path.join(desktop, "src-tauri/Entitlements.plist"),
      app,
    ]);
    run("codesign", ["--verify", "--deep", "--strict", app]);
    mkdirSync(releaseDirectory, { recursive: true });
    const localApp = path.join(releaseDirectory, path.basename(app));
    const localZip = path.join(
      releaseDirectory,
      `Buzz-Custom_${version}_aarch64.zip`,
    );
    run("ditto", [app, localApp]);
    run("ditto", [
      "-c",
      "-k",
      "--sequesterRsrc",
      "--keepParent",
      localApp,
      localZip,
    ]);
    writeFileSync(
      path.join(releaseDirectory, "source-commit.txt"),
      `${output("git", ["rev-parse", "HEAD"])}\n`,
    );
    if (mode === "--notarize") notarize(releaseDirectory, version);
    else console.log(`Ready for local use: ${localZip}`);
  } finally {
    try {
      run("security", ["delete-keychain", keychain], { stdio: "ignore" });
    } catch {}
    rmSync(temporary, { recursive: true, force: true });
  }
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  process.umask(0o077);
  const [version, ...extra] = process.argv.slice(2);
  if (
    extra.length > 1 ||
    (extra.length === 1 && !["--resume", "--notarize"].includes(extra[0]))
  ) {
    throw new Error(
      "Use: release-bl4ko-desktop.mjs <upstream-version>-bl4ko.N [--notarize|--resume]",
    );
  }
  try {
    await release(version, extra[0]);
  } catch (error) {
    console.error(error instanceof Error ? error.message : "Release failed");
    process.exitCode = 1;
  }
}
