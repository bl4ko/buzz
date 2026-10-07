import { execFileSync } from "node:child_process";
import { createHash, sign, X509Certificate } from "node:crypto";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  renameSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createSigningKeychain } from "./release-bl4ko-desktop.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const desktop = path.join(root, "desktop");
const identifier = "com.bl4ko.buzz";
const appId = "6817066676";
const profileName = "Bl4uzz macOS App Store";
const appleRoot = "envs/external/apple/restricted/";

export function testflightConfig(build) {
  if (!/^[1-9]\d{0,17}$/.test(build ?? ""))
    throw new Error("Use a positive numeric Mac build number");
  return { bundle: { macOS: { bundleVersion: build } } };
}

export function validateDistributionProfile(
  profile,
  certificate,
  now = Date.now(),
) {
  if (
    profile.Entitlements?.["com.apple.application-identifier"] !==
      "55S37D9HA7.com.bl4ko.buzz" ||
    profile.Entitlements?.["com.apple.developer.team-identifier"] !==
      "55S37D9HA7" ||
    !profile.TeamIdentifier?.includes("55S37D9HA7")
  )
    throw new Error("Mac provisioning profile identity mismatch");
  if (!(Date.parse(profile.ExpirationDate) > now))
    throw new Error("Mac provisioning profile is expired");
  if (
    profile.Entitlements["get-task-allow"] === true ||
    profile.ProvisionedDevices ||
    profile.ProvisionsAllDevices === true
  )
    throw new Error("Use a Mac App Store distribution profile");
  if (
    !profile.DeveloperCertificates?.some((value) =>
      Buffer.from(value, "base64").equals(certificate),
    )
  )
    throw new Error(
      "Mac provisioning profile does not allow the signing certificate",
    );
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

function vaultEnv() {
  const env = { ...process.env, VAULT_ADDR: "https://vault.xqx.uk:8200" };
  delete env.VAULT_TOKEN;
  delete env.TF_VAR_vault_token;
  return env;
}

function secret(name) {
  return JSON.parse(
    output("vault", ["kv", "get", "-format=json", `kv/${appleRoot}${name}`], {
      env: vaultEnv(),
    }),
  ).data.data;
}

async function release(build, upload) {
  const config = testflightConfig(build);
  if (process.platform !== "darwin" || process.arch !== "arm64")
    throw new Error("Build on the Apple silicon Mac mini");
  if (upload !== undefined && upload !== "--upload")
    throw new Error("Use --upload for Apple TestFlight delivery");
  if (output("git", ["status", "--porcelain"]))
    throw new Error("Use a clean, committed checkout");
  const identity = JSON.parse(
    output("vault", ["token", "lookup", "-format=json"], { env: vaultEnv() }),
  ).data;
  if (
    identity.path !== "auth/approle/login" ||
    identity.meta?.role_name !== "mac-mini-temp" ||
    identity.ttl < 3600
  )
    throw new Error("Use the mac-mini-temp token with one hour remaining");
  const version = JSON.parse(
    readFileSync(path.join(desktop, "package.json")),
  ).version;
  const directory = path.join(
    root,
    "..",
    "buzz-builds",
    "macos-testflight",
    version,
    build,
  );
  const commit = output("git", ["rev-parse", "HEAD"]);
  const app = path.join(directory, "Bl4uzz.app");
  const pkg = path.join(directory, "Bl4uzz.pkg");
  if (existsSync(directory)) {
    if (
      (!upload && existsSync(pkg)) ||
      readFileSync(path.join(directory, "source-commit.txt"), "utf8").trim() !==
        commit
    )
      throw new Error(
        "The build folder already exists or has different source",
      );
  } else {
    mkdirSync(directory, { recursive: true });
    writeFileSync(path.join(directory, "source-commit.txt"), `${commit}\n`);
  }
  const temporary = mkdtempSync(path.join(tmpdir(), "buzz-mac-testflight-"));
  const keychains = output("security", ["list-keychains", "-d", "user"])
    .split("\n")
    .map((line) => line.trim().replace(/^"|"$/g, ""))
    .filter(existsSync);
  const signingKeychains = [];
  try {
    const api = secret("api-keys/appstoreconnect");
    const encode = (value) =>
      Buffer.from(JSON.stringify(value)).toString("base64url");
    async function apple(route, body) {
      const now = Math.floor(Date.now() / 1000);
      const input = `${encode({ alg: "ES256", kid: api["key-id"], typ: "JWT" })}.${encode({ iss: api["issuer-id"], iat: now, exp: now + 1200, aud: "appstoreconnect-v1" })}`;
      const token = `${input}.${sign("sha256", Buffer.from(input), { key: api["private-key"], dsaEncoding: "ieee-p1363" }).toString("base64url")}`;
      const response = await fetch(
        `https://api.appstoreconnect.apple.com/v1/${route}`,
        {
          method: body ? "POST" : "GET",
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          body: body ? JSON.stringify(body) : undefined,
        },
      );
      const result = response.status === 204 ? null : await response.json();
      if (!response.ok)
        throw new Error(
          `Apple HTTP ${response.status}: ${JSON.stringify(result.errors)}`,
        );
      return result;
    }
    if (!existsSync(pkg)) {
      const appSigning = secret("signing/mac-app-distribution");
      const installerSigning = secret("signing/mac-installer-distribution");
      const bundles = await apple(`bundleIds?filter[identifier]=${identifier}`);
      const bundle = bundles.data.find(
        (item) => item.attributes.identifier === identifier,
      );
      if (!bundle) throw new Error("The Buzz Mac App ID is missing");
      const buildProfileName = `${profileName} ${build}`;
      const profiles = await apple(
        `profiles?filter[name]=${encodeURIComponent(buildProfileName)}&include=bundleId,certificates`,
      );
      let profile = profiles.data.find(
        (item) =>
          item.attributes.profileState === "ACTIVE" &&
          Date.parse(item.attributes.expirationDate) > Date.now() &&
          item.attributes.profileType === "MAC_APP_STORE" &&
          item.relationships.bundleId.data.id === bundle.id &&
          item.relationships.certificates.data.some(
            (cert) => cert.id === appSigning["certificate-id"],
          ),
      );
      if (!profile) {
        profile = (
          await apple("profiles", {
            data: {
              type: "profiles",
              attributes: {
                name: buildProfileName,
                profileType: "MAC_APP_STORE",
              },
              relationships: {
                bundleId: { data: { type: "bundleIds", id: bundle.id } },
                certificates: {
                  data: [
                    { type: "certificates", id: appSigning["certificate-id"] },
                  ],
                },
              },
            },
          })
        ).data;
      }
      const provisioning = Buffer.from(
        profile.attributes.profileContent,
        "base64",
      );
      const profilePath = path.join(temporary, "embedded.provisionprofile");
      writeFileSync(profilePath, provisioning);
      const decodedProfilePath = path.join(temporary, "profile.plist");
      writeFileSync(
        decodedProfilePath,
        output("security", ["cms", "-D", "-i", profilePath]),
      );
      const profileField = (key, format = "raw") =>
        output("plutil", [
          "-extract",
          key,
          format,
          "-o",
          "-",
          decodedProfilePath,
        ]);
      const decodedProfile = {
        Entitlements: JSON.parse(profileField("Entitlements", "json")),
        TeamIdentifier: JSON.parse(profileField("TeamIdentifier", "json")),
        ExpirationDate: profileField("ExpirationDate"),
        DeveloperCertificates: [profileField("DeveloperCertificates.0")],
        UUID: profileField("UUID"),
      };
      validateDistributionProfile(
        decodedProfile,
        Buffer.from(appSigning.certificate, "base64"),
      );
      config.bundle.macOS.files = { "embedded.provisionprofile": profilePath };
      const configPath = path.join(temporary, "tauri.build.json");
      writeFileSync(configPath, JSON.stringify(config));
      const env = { ...process.env };
      for (const name of [
        "BUZZ_UPDATER_PUBLIC_KEY",
        "BUZZ_UPDATER_ENDPOINT",
        "TAURI_SIGNING_PRIVATE_KEY",
        "TAURI_SIGNING_PRIVATE_KEY_PASSWORD",
      ])
        delete env[name];
      run("pnpm", ["run", "typecheck"], { cwd: desktop });
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
      run(
        "pnpm",
        [
          "tauri",
          "build",
          "--bundles",
          "app",
          "--config",
          "src-tauri/tauri.appstore.conf.json",
          "--config",
          configPath,
          "--no-sign",
          "--ci",
        ],
        { cwd: desktop, env },
      );
      run("ditto", [
        path.join(desktop, "src-tauri/target/release/bundle/macos/Bl4uzz.app"),
        app,
      ]);
      const plist = path.join(app, "Contents/Info.plist");
      for (const field of ["CFBundleName", "CFBundleDisplayName"])
        run("plutil", ["-replace", field, "-string", "Bl4uzz", plist]);
      run("plutil", [
        "-insert",
        "ITSAppUsesNonExemptEncryption",
        "-bool",
        "NO",
        plist,
      ]);
      const intermediateResponse = await fetch(
        "https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer",
      );
      if (!intermediateResponse.ok)
        throw new Error("Apple certificate authority download failed");
      const intermediate = Buffer.from(
        await intermediateResponse.arrayBuffer(),
      );
      const intermediatePath = path.join(temporary, "wwdr.cer");
      writeFileSync(intermediatePath, intermediate);
      const hashes = [];
      for (const [index, signing] of [appSigning, installerSigning].entries()) {
        const certificate = new X509Certificate(
          Buffer.from(signing.certificate, "base64"),
        );
        if (
          !(Date.parse(certificate.validFrom) <= Date.now()) ||
          !(Date.parse(certificate.validTo) > Date.now())
        )
          throw new Error(
            "Mac signing certificate is outside its validity period",
          );
        if (!certificate.verify(new X509Certificate(intermediate).publicKey))
          throw new Error("Mac signing certificate authority mismatch");
        const certificatePath = path.join(temporary, `${index}.pem`);
        const privateKeyPath = path.join(temporary, `${index}.key`);
        const keychain = path.join(temporary, `${index}.keychain-db`);
        signingKeychains.push(keychain);
        writeFileSync(certificatePath, certificate.toString());
        writeFileSync(privateKeyPath, signing["private-key"], { mode: 0o600 });
        createSigningKeychain(
          certificatePath,
          privateKeyPath,
          path.join(temporary, `${index}.p12`),
          keychain,
          index === 0
            ? ["/usr/bin/codesign"]
            : ["/usr/bin/productbuild", "/usr/bin/productsign"],
        );
        run("security", ["import", intermediatePath, "-k", keychain]);
        hashes.push(certificate.fingerprint.replaceAll(":", ""));
      }
      const binaries = path.join(app, "Contents/MacOS");
      for (const binary of readdirSync(binaries).filter(
        (name) => name !== "buzz-desktop",
      ))
        run("codesign", [
          "--force",
          "--keychain",
          signingKeychains[0],
          "--sign",
          hashes[0],
          "--timestamp",
          "--entitlements",
          path.join(desktop, "src-tauri/Entitlements.sidecar.plist"),
          path.join(binaries, binary),
        ]);
      run("codesign", [
        "--force",
        "--keychain",
        signingKeychains[0],
        "--sign",
        hashes[0],
        "--timestamp",
        "--entitlements",
        path.join(desktop, "src-tauri/Entitlements.appstore.plist"),
        app,
      ]);
      run("codesign", ["--verify", "--deep", "--strict", app]);
      run(
        "xcrun",
        [
          "productbuild",
          "--sign",
          hashes[1],
          "--keychain",
          signingKeychains[1],
          "--component",
          app,
          "/Applications",
          path.join(temporary, "Buzz-Desktop.pkg"),
        ],
        { env: { ...process.env, TMPDIR: temporary + path.sep } },
      );
      run("pkgutil", [
        "--check-signature",
        path.join(temporary, "Buzz-Desktop.pkg"),
      ]);
      copyFileSync(path.join(temporary, "Buzz-Desktop.pkg"), `${pkg}.partial`);
      renameSync(`${pkg}.partial`, pkg);
      writeFileSync(
        path.join(directory, "release-checks.json"),
        `${JSON.stringify(
          {
            commit,
            build,
            version,
            sha256: createHash("sha256")
              .update(readFileSync(pkg))
              .digest("hex"),
            profileId: profile.id,
            profileUUID: decodedProfile.UUID,
            profileExpires: decodedProfile.ExpirationDate,
            checks: [
              "fresh build-specific Mac App Store profile",
              "profile app and team identity",
              "profile allows signing certificate",
              "profile and certificate validity periods",
              "codesign deep strict verification",
              "installer signature",
            ],
          },
          null,
          2,
        )}\n`,
      );
    }
    if (upload) {
      const privateKeys = path.join(temporary, "private_keys");
      mkdirSync(privateKeys);
      writeFileSync(
        path.join(privateKeys, `AuthKey_${api["key-id"]}.p8`),
        api["private-key"],
        { mode: 0o600 },
      );
      run(
        "xcrun",
        [
          "altool",
          "--validate-app",
          "--type",
          "macos",
          "--file",
          pkg,
          "--apiKey",
          api["key-id"],
          "--apiIssuer",
          api["issuer-id"],
        ],
        { cwd: temporary },
      );
      run(
        "xcrun",
        [
          "altool",
          "--upload-app",
          "--type",
          "macos",
          "--file",
          pkg,
          "--apiKey",
          api["key-id"],
          "--apiIssuer",
          api["issuer-id"],
        ],
        { cwd: temporary },
      );
      const builds = await apple(
        `builds?filter[app]=${appId}&filter[version]=${build}`,
      );
      writeFileSync(
        path.join(directory, "testflight.json"),
        `${JSON.stringify(builds, null, 2)}\n`,
      );
      console.log(
        `Uploaded ${version} (${build}). Check Apple processing before adding testers.`,
      );
    } else console.log(`Signed package ready: ${pkg}`);
  } finally {
    run("security", ["list-keychains", "-d", "user", "-s", ...keychains]);
    for (const keychain of signingKeychains) {
      if (existsSync(keychain)) run("security", ["delete-keychain", keychain]);
    }
    rmSync(temporary, { recursive: true, force: true });
  }
}

if (
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
)
  await release(...process.argv.slice(2));
