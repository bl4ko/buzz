import { execFileSync } from "node:child_process";
import {
  createPrivateKey,
  randomBytes,
  sign,
  X509Certificate,
} from "node:crypto";
import {
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
const repository = "bl4ko/buzz";
const applePath =
  "envs/external/apple/restricted/signing/developer-id-application";
const updaterPath = "envs/external/tauri/restricted/signing/buzz";
const botPath = "envs/external/github/bl4ko/restricted/apps/bl4ko-release-bot";
const versionPattern = /^(\d+\.\d+\.\d+)-bl4ko\.([1-9]\d*)$/;

export function releaseInfo(version, upstreamVersion) {
  const match = versionPattern.exec(version ?? "");
  if (!match || match[1] !== upstreamVersion) {
    throw new Error(
      `Version must be ${upstreamVersion}-bl4ko.N, with N starting at 1`,
    );
  }
  const tag = `custom-desktop-v${version}`;
  const archive = `Buzz-Custom_${version}_aarch64.app.tar.gz`;
  return {
    version,
    tag,
    archive,
    url: `https://github.com/${repository}/releases/download/${tag}/${archive}`,
    endpoint: `https://github.com/${repository}/releases/download/buzz-custom-desktop-latest/latest.json`,
  };
}

export function advancesVersion(version, current) {
  if (!versionPattern.test(version) || !versionPattern.test(current)) {
    throw new Error("Updater versions must use the Buzz Custom version format");
  }
  const next = version.split(/\.|-bl4ko\./).map(BigInt);
  const previous = current.split(/\.|-bl4ko\./).map(BigInt);
  const different = next.findIndex((value, index) => value !== previous[index]);
  return different !== -1 && next[different] > previous[different];
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

function jwt(header, payload, privateKey, algorithm) {
  const data = [header, payload]
    .map((value) => Buffer.from(JSON.stringify(value)).toString("base64url"))
    .join(".");
  return `${data}.${sign(algorithm, Buffer.from(data), createPrivateKey(privateKey)).toString("base64url")}`;
}

async function releaseBotEnv() {
  const bot = secret(botPath);
  const now = Math.floor(Date.now() / 1000);
  const token = jwt(
    { alg: "RS256", typ: "JWT" },
    { iss: String(bot.github_app_id), iat: now - 60, exp: now + 540 },
    bot.github_app_private_key,
    "RSA-SHA256",
  );
  const headers = {
    Authorization: `Bearer ${token}`,
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
  };
  const installationsResponse = await fetch(
    "https://api.github.com/app/installations",
    { headers },
  );
  if (!installationsResponse.ok)
    throw new Error(
      `Release bot installation lookup failed: HTTP ${installationsResponse.status}`,
    );
  const installation = (await installationsResponse.json()).find(
    (item) => item.account.login === "bl4ko",
  );
  if (!installation) throw new Error("Release bot is not installed on bl4ko");
  const response = await fetch(
    `https://api.github.com/app/installations/${installation.id}/access_tokens`,
    {
      method: "POST",
      headers: { ...headers, "Content-Type": "application/json" },
      body: JSON.stringify({
        repositories: ["buzz"],
        permissions: { contents: "write" },
      }),
    },
  );
  if (!response.ok)
    throw new Error(
      `Release bot cannot access bl4ko/buzz: HTTP ${response.status}. Enable buzz in the bot's installation settings`,
    );
  return { ...process.env, GH_TOKEN: (await response.json()).token };
}

async function release(version, publish) {
  if (process.platform !== "darwin" || process.arch !== "arm64")
    throw new Error("Build on the Apple silicon Mac mini");
  const upstreamVersion = JSON.parse(
    readFileSync(path.join(desktop, "package.json")),
  ).version;
  const info = releaseInfo(version, upstreamVersion);
  if (output("git", ["status", "--porcelain"]))
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
  if (publish) await releaseBotEnv();
  const signing = secret(applePath);
  if (!signing.certificate)
    throw new Error(
      "Apple Developer ID certificate is missing. Complete the Account Holder step in FORK.md",
    );
  const updater = secret(updaterPath);
  const apple = secret(
    "envs/external/apple/restricted/api-keys/appstoreconnect",
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
    const appleKey = path.join(temporary, "AuthKey.p8");
    writeFileSync(appleKey, apple["private-key"], { mode: 0o600 });
    const env = {
      ...process.env,
      BUZZ_UPDATER_PUBLIC_KEY: updater["public-key"],
      BUZZ_UPDATER_ENDPOINT: info.endpoint,
      TAURI_SIGNING_PRIVATE_KEY: updater["private-key"],
      TAURI_SIGNING_PRIVATE_KEY_PASSWORD: "",
    };
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
    run("pnpm", ["exec", "node", "scripts/build-release-config.mjs"], {
      cwd: desktop,
      env,
    });
    const config = JSON.parse(
      readFileSync(path.join(desktop, "src-tauri/tauri.release.conf.json")),
    );
    config.productName = "Buzz Custom";
    config.identifier = "xyz.bl4ko.buzz.custom";
    config.version = version;
    config.bundle.createUpdaterArtifacts = false;
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
    const bundle = path.dirname(path.dirname(app));
    const zip = path.join(bundle, `Buzz-Custom_${version}_aarch64.zip`);
    run("ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", app, zip]);
    run("xcrun", [
      "notarytool",
      "submit",
      zip,
      "--key",
      appleKey,
      "--key-id",
      apple["key-id"],
      "--issuer",
      apple["issuer-id"],
      "--wait",
      "--timeout",
      "30m",
    ]);
    run("xcrun", ["stapler", "staple", app]);
    run("xcrun", ["stapler", "validate", app]);
    run("codesign", ["--verify", "--deep", "--strict", app]);
    run("ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", app, zip]);
    const archive = path.join(bundle, info.archive);
    run("tar", ["-czf", archive, "-C", path.dirname(app), path.basename(app)]);
    run("pnpm", ["tauri", "signer", "sign", archive], { cwd: desktop, env });
    const manifest = path.join(bundle, "latest.json");
    writeFileSync(
      manifest,
      output("bash", [
        "desktop/scripts/generate-oss-latest-json.sh",
        version,
        `darwin-aarch64:${archive}.sig:${info.url}`,
      ]),
    );
    console.log(`Ready: ${zip}`);
    if (!publish) return;
    const githubEnv = await releaseBotEnv();
    const commit = output("git", ["rev-parse", "HEAD"]);
    output("gh", ["api", `repos/${repository}/git/commits/${commit}`], {
      env: githubEnv,
    });
    const notes = path.join(temporary, "notes.md");
    writeFileSync(
      notes,
      `Buzz Custom ${version} for Apple silicon.\n\nChannel agents join new huddles automatically.\n\nSource: https://github.com/${repository}/commit/${commit}\n\nDeveloper ID signed and notarized. Live voice testing remains a manual check.\n`,
    );
    run(
      "gh",
      [
        "release",
        "create",
        info.tag,
        zip,
        archive,
        `${archive}.sig`,
        "--repo",
        repository,
        "--target",
        commit,
        "--title",
        `Buzz Custom ${version}`,
        "--notes-file",
        notes,
        "--prerelease",
        "--draft",
      ],
      { env: githubEnv },
    );
    run(
      "gh",
      [
        "release",
        "edit",
        info.tag,
        "--repo",
        repository,
        "--draft=false",
        "--latest=false",
      ],
      { env: githubEnv },
    );
    const releases = JSON.parse(
      output("gh", ["api", `repos/${repository}/releases`], { env: githubEnv }),
    );
    const rolling = releases.find(
      (item) => item.tag_name === "buzz-custom-desktop-latest",
    );
    if (rolling) {
      const currentDir = path.join(temporary, "current");
      run(
        "gh",
        [
          "release",
          "download",
          "buzz-custom-desktop-latest",
          "--repo",
          repository,
          "--pattern",
          "latest.json",
          "--dir",
          currentDir,
        ],
        { env: githubEnv },
      );
      const current = JSON.parse(
        readFileSync(path.join(currentDir, "latest.json")),
      );
      if (!advancesVersion(version, current.version))
        throw new Error(
          "Published release would not advance the updater version",
        );
      run(
        "gh",
        [
          "release",
          "upload",
          "buzz-custom-desktop-latest",
          manifest,
          "--repo",
          repository,
          "--clobber",
        ],
        { env: githubEnv },
      );
    } else {
      run(
        "gh",
        [
          "release",
          "create",
          "buzz-custom-desktop-latest",
          manifest,
          "--repo",
          repository,
          "--target",
          commit,
          "--title",
          "Buzz Custom updates",
          "--notes",
          "Signed desktop update manifest.",
          "--prerelease",
          "--latest=false",
        ],
        { env: githubEnv },
      );
    }
    const servedDir = path.join(temporary, "served");
    run(
      "gh",
      [
        "release",
        "download",
        "buzz-custom-desktop-latest",
        "--repo",
        repository,
        "--pattern",
        "latest.json",
        "--dir",
        servedDir,
      ],
      { env: githubEnv },
    );
    if (
      !readFileSync(manifest).equals(
        readFileSync(path.join(servedDir, "latest.json")),
      )
    )
      throw new Error(
        "Published updater manifest differs from the verified build",
      );
    console.log(
      `Published: https://github.com/${repository}/releases/tag/${info.tag}`,
    );
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
  const [version, flag] = process.argv.slice(2);
  if (flag && flag !== "--publish")
    throw new Error(
      "Use: release-bl4ko-desktop.mjs <upstream-version>-bl4ko.N [--publish]",
    );
  try {
    await release(version, flag === "--publish");
  } catch (error) {
    console.error(error instanceof Error ? error.message : "Release failed");
    process.exitCode = 1;
  }
}
