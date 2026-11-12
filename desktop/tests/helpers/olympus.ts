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
