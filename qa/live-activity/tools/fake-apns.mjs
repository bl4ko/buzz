import http from "node:http";
import { createHash } from "node:crypto";
import { appendFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { execFile } from "node:child_process";
import path from "node:path";

const [port, log, udid, bundle, postureFile] = process.argv.slice(2);
let queue = Promise.resolve();
let sequence = 0;

const run = (args) =>
  new Promise((resolve) =>
    execFile("xcrun", ["simctl", ...args], (error, stdout, stderr) =>
      resolve({ ok: !error, out: stdout.trim(), err: stderr.trim().split("\n").pop() }),
    ),
  );
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const posture = () => (existsSync(postureFile) ? readFileSync(postureFile, "utf8").trim() : "app");
const restore = async () => {
  const button = { locked: "LOCK", home: "HOME" }[posture()];
  if (!button) return;
  await sleep(500);
  await new Promise((resolve) => execFile("idb", ["ui", "button", "--udid", udid, button], () => resolve()));
};

const pushAlert = async (body) => {
  const dir = mkdtempSync(path.join(process.env.TMPDIR || "/tmp", "apns-"));
  writeFileSync(path.join(dir, "payload.json"), body);
  const result = await run(["push", udid, bundle, path.join(dir, "payload.json")]);
  rmSync(dir, { recursive: true, force: true });
  return result.ok ? "ok" : `error: ${result.err}`;
};

const applied = (folder, name) => {
  const file = path.join(folder, "applied.jsonl");
  if (!existsSync(file)) return null;
  for (const line of readFileSync(file, "utf8").split("\n").filter(Boolean).reverse()) {
    const entry = JSON.parse(line);
    if (entry.file === name) return entry.result;
  }
  return null;
};

const waitApplied = async (folder, name, ms) => {
  for (let waited = 0; waited < ms; waited += 250) {
    const result = applied(folder, name);
    if (result) return result;
    await sleep(250);
  }
  return null;
};

const deliverLiveActivity = async (fingerprint, body) => {
  const container = await run(["get_app_container", udid, bundle, "data"]);
  if (!container.ok) return "error: app not installed";
  const folder = path.join(container.out, "Library", "QaLiveActivity");
  mkdirSync(path.join(folder, "inbox"), { recursive: true });
  const name = `${Date.now()}-${String(++sequence).padStart(4, "0")}.json`;
  const staged = path.join(folder, name);
  writeFileSync(staged, JSON.stringify({ token: fingerprint, aps: JSON.parse(body).aps }));
  renameSync(staged, path.join(folder, "inbox", name));
  await run(["spawn", udid, "notifyutil", "-p", "com.bl4ko.buzz.qa.live-activity"]);
  const quick = await waitApplied(folder, name, 1500);
  if (quick) return quick;
  await run(["launch", udid, bundle]);
  const result = (await waitApplied(folder, name, 20000)) || "timeout";
  await restore();
  return result;
};

http
  .createServer((req, res) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => {
      const match = req.url.match(/^\/3\/device\/([0-9a-f]+)$/);
      if (req.method !== "POST" || !match) {
        res.writeHead(404, { "content-type": "application/json" });
        return res.end(JSON.stringify({ reason: "BadPath" }));
      }
      const body = Buffer.concat(chunks).toString("utf8");
      const type = req.headers["apns-push-type"];
      const topic = req.headers["apns-topic"];
      const fingerprint = createHash("sha256").update(Buffer.from(match[1], "hex")).digest("hex");
      const record = {
        at: Date.now() / 1000,
        type,
        topic,
        topic_ok: topic === (type === "liveactivity" ? `${bundle}.push-type.liveactivity` : bundle),
        priority: Number(req.headers["apns-priority"]),
        token: fingerprint.slice(0, 12),
        jwt: type === "liveactivity" ? /^bearer [\w-]+\.[\w-]+\.[\w-]+$/.test(req.headers.authorization || "") : undefined,
        payload: JSON.parse(body),
      };
      res.writeHead(200, { "apns-id": req.headers["apns-id"] || "" });
      res.end();
      queue = queue.then(async () => {
        record.replay = type === "liveactivity" ? await deliverLiveActivity(fingerprint, body) : await pushAlert(body);
        appendFileSync(log, JSON.stringify(record) + "\n");
      });
    });
  })
  .listen(Number(port), "127.0.0.1", () => console.log(`fake apns on ${port}`));
