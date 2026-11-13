import type { RelayEvent } from "../../src/shared/api/types";

export const OLYMPUS_OPERATOR = "b346cba6".repeat(8);
export const OLYMPUS_OWNER = "deadbeef".repeat(8);
export const PROOF_PUBLIC_KEY = "51a7e0c1".repeat(8);

let nextId = 1;
function eventId() {
  nextId += 1;
  return nextId.toString(16).padStart(64, "0");
}

function minutesAgo(minutes: number) {
  return new Date(Date.now() - minutes * 60_000).toISOString();
}

function stateEvent(
  kind: number,
  d: string,
  content: unknown,
  extraTags: string[][],
  createdAt: number,
): RelayEvent {
  return {
    id: eventId(),
    pubkey: OLYMPUS_OPERATOR,
    kind,
    created_at: createdAt,
    content: JSON.stringify(content),
    tags: [
      ["d", d],
      ["p", OLYMPUS_OWNER],
      ["p", OLYMPUS_OPERATOR],
      ...extraTags,
      ["status", "active"],
    ],
    sig: "0".repeat(128),
  };
}

export function olympusWorkspaceEvent(
  input: { phase?: string; suspend?: boolean; createdAt?: number } = {},
) {
  return stateEvent(
    30191,
    "dev",
    {
      v: 1,
      name: "dev",
      namespace: "olympus-dev",
      owner: OLYMPUS_OWNER,
      managedBy: null,
      spec: { suspend: input.suspend ?? false, quota: null },
      status: {
        phase: input.phase ?? "Ready",
        reason: null,
        channelId: "c0ffee00-0000-4000-8000-000000000001",
        schedulerPublicKey: null,
        mirrorPublicKey: null,
        conditions: [],
      },
      providers: [
        {
          name: "anthropic",
          models: ["claude-haiku-5-5", "claude-opus-5-5"],
          protocols: ["anthropic"],
        },
        { name: "openai", models: [], protocols: ["openai"] },
      ],
      mcpServers: ["share", "hindsight", "search"],
    },
    [],
    input.createdAt ?? Math.floor(Date.now() / 1000) - 600,
  );
}

export function olympusProofEvent(
  input: { phase?: string; reason?: string | null; createdAt?: number } = {},
) {
  const phase = input.phase ?? "Online";
  return stateEvent(
    30190,
    "olympus-dev/proof",
    {
      v: 1,
      workspace: "dev",
      namespace: "olympus-dev",
      name: "proof",
      owner: OLYMPUS_OWNER,
      managedBy: null,
      spec: {
        harness: "claude-code",
        model: "claude-haiku-5-5",
        effort: "high",
        pool: "anthropic",
        instructions:
          "You are proof, the Olympus test agent.\nAnswer pings in the workspace channel.\nKeep answers short.",
        owner: null,
        egress: [{ host: "share.xqx.uk", ports: [443] }],
        mcpServers: [{ name: "share", tools: ["upload_file", "list_files"] }],
        services: [],
        gitSources: [{ name: "proof-notes", access: "write" }],
        skills: [{ repo: "skills", name: "buzz" }],
        suspend: phase === "Suspended",
        memory: { bank: "private" },
      },
      schedules: [
        {
          name: "ping",
          cron: "*/5 * * * *",
          timeZone: "Europe/Ljubljana",
          suspend: false,
          workspace: true,
          prompt: "Post a short status line.",
          script: null,
          lastRunTime: minutesAgo(4),
          lastResult: "Succeeded",
        },
      ],
      status: {
        phase,
        reason: input.reason ?? (phase === "Suspended" ? "Suspended" : null),
        publicKey: PROOF_PUBLIC_KEY,
        lastActivity: minutesAgo(2),
        conditions: [
          {
            type: "Enrolled",
            status: "True",
            reason: "Enrolled",
            message: "",
            lastTransitionTime: minutesAgo(600),
          },
          {
            type: "Ready",
            status: "True",
            reason: "Available",
            message: "",
            lastTransitionTime: minutesAgo(500),
          },
          {
            type: "Online",
            status: phase === "Online" ? "True" : "False",
            reason: phase === "Online" ? "Connected" : "Suspended",
            message: "",
            lastTransitionTime: minutesAgo(3),
          },
        ],
      },
    },
    [["workspace", "dev"]],
    input.createdAt ?? Math.floor(Date.now() / 1000) - 300,
  );
}

export function olympusCodexEvent() {
  return stateEvent(
    30190,
    "olympus-dev/codex2",
    {
      v: 1,
      workspace: "dev",
      namespace: "olympus-dev",
      name: "codex2",
      owner: OLYMPUS_OWNER,
      managedBy: null,
      spec: {
        harness: "codex",
        model: "gpt-5.5",
        effort: null,
        pool: "openai",
        instructions: null,
        mcpServers: [],
        services: [],
        suspend: true,
        memory: null,
      },
      schedules: [],
      status: {
        phase: "Suspended",
        reason: "Suspended by the owner",
        publicKey: null,
        lastActivity: null,
        conditions: [],
      },
    },
    [["workspace", "dev"]],
    Math.floor(Date.now() / 1000) - 300,
  );
}

export function olympusDevEvents() {
  return [olympusWorkspaceEvent(), olympusProofEvent(), olympusCodexEvent()];
}

export function olympusResultEvent(input: {
  requestId: string;
  status: "accepted" | "refused";
  reason: string;
  action: string;
  agent?: string;
}): RelayEvent {
  return {
    id: eventId(),
    pubkey: OLYMPUS_OPERATOR,
    kind: 44311,
    created_at: Math.floor(Date.now() / 1000),
    content: JSON.stringify({
      v: 1,
      status: input.status,
      reason: input.reason,
      request: input.requestId,
    }),
    tags: [
      ["e", input.requestId],
      ["p", OLYMPUS_OWNER],
      ["p", OLYMPUS_OPERATOR],
      ["status", input.status],
      ["action", input.action],
      ["workspace", "dev"],
      ...(input.agent ? [["agent", input.agent]] : []),
    ],
    sig: "0".repeat(128),
  };
}

export const MASTER_PUBLIC_KEY =
  "8f83d6b7f3d74f7d933ae3a54dd8c6cc85c7f98e531c16e5a827b953441a8d67";

export function olympusMasterEvent() {
  const event = olympusProofEvent();
  const content = JSON.parse(event.content);
  content.name = "boss";
  content.role = "master";
  content.status.publicKey = MASTER_PUBLIC_KEY;
  content.spec.profile = { displayName: "Spec name", picture: null };
  return {
    ...event,
    content: JSON.stringify(content),
    tags: event.tags.map((tag) =>
      tag[0] === "d" ? ["d", "olympus-dev/boss"] : tag,
    ),
  };
}

export const PROPOSAL_DIGEST = "d1".repeat(32);

export function olympusProposalEvent(
  input: {
    name?: string;
    requesterKey?: string;
    phase?: string;
    highRisk?: string[];
    result?: { reason: string; request: string; at: number } | null;
    expiresAt?: number;
    createdAt?: number;
    eventCreatedAt?: number;
  } = {},
): RelayEvent {
  const now = Math.floor(Date.now() / 1000);
  const name = input.name ?? "p-aada7279a890";
  const createdAt = input.createdAt ?? now - 300;
  return {
    id: eventId(),
    pubkey: OLYMPUS_OPERATOR,
    kind: 30192,
    created_at: input.eventCreatedAt ?? createdAt,
    content: JSON.stringify({
      v: 1,
      name,
      requester: "zeus/zeus",
      requesterKey: input.requesterKey ?? MASTER_PUBLIC_KEY,
      target: {
        kind: "Agent",
        namespace: "olympus-dev",
        name: "proof",
        workspace: "dev",
      },
      operation: "patch",
      patch: { spec: { suspend: true } },
      reason: "Proof is idle. **Suspend** it <b>now</b>.",
      diff: [{ path: "spec.suspend", from: "false", to: "true" }],
      highRisk: input.highRisk ?? [],
      createdAt,
      expiresAt: input.expiresAt ?? createdAt + 86_400,
      digest: PROPOSAL_DIGEST,
      phase: input.phase ?? "pending",
      result: input.result ?? null,
    }),
    tags: [
      ["d", name],
      ["p", OLYMPUS_OWNER],
      ["p", OLYMPUS_OPERATOR],
      ["workspace", "dev"],
      ["requester", input.requesterKey ?? MASTER_PUBLIC_KEY],
      ["status", "active"],
    ],
    sig: "0".repeat(128),
  };
}

type UsageWindow = {
  tokens: Record<string, Record<string, number>>;
  turns: number;
  apiErrors: number;
  runs: number;
  failedRuns: number;
  share: number;
};

export function olympusUsageEvent(input: {
  workspace: string;
  name: string;
  harness?: string;
  windows: { "24h"?: UsageWindow; "7d"?: UsageWindow };
  lastRun?: { schedule: string; at: number; result: string } | null;
}): RelayEvent {
  const now = Math.floor(Date.now() / 1000);
  const namespace = `olympus-${input.workspace}`;
  return stateEvent(
    30193,
    `${namespace}/${input.name}`,
    {
      v: 1,
      workspace: input.workspace,
      namespace,
      name: input.name,
      harness: input.harness ?? "claude-code",
      at: now - 240,
      windows: input.windows,
      lastRun: input.lastRun ?? null,
    },
    [["workspace", input.workspace]],
    now - 240,
  );
}

export function olympusHecateEvent(
  accounts: {
    provider: string;
    credential: string;
    window: string;
    usedRatio: number;
  }[],
): RelayEvent {
  const now = Math.floor(Date.now() / 1000);
  return stateEvent(
    30193,
    "hecate",
    { v: 1, at: now - 240, accounts },
    [],
    now - 240,
  );
}
