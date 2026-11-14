import type { RelayEvent } from "../../src/shared/api/types";
import { OLYMPUS_OPERATOR, OLYMPUS_OWNER } from "./olympus";

export const ARGUS_PUBLIC_KEY = "a26a5000".repeat(8);
export const ZEUS_PUBLIC_KEY = "2e0500aa".repeat(8);
export const OPS_SCHEDULER = "5c4ed000".repeat(8);

let nextId = 0x0a00;
function eventId() {
  nextId += 1;
  return nextId.toString(16).padStart(64, "a");
}

function ago(minutes: number) {
  return new Date(Date.now() - minutes * 60_000).toISOString();
}

function state(
  kind: number,
  d: string,
  content: unknown,
  extra: string[][] = [],
): RelayEvent {
  return {
    id: eventId(),
    pubkey: OLYMPUS_OPERATOR,
    kind,
    created_at: Math.floor(Date.now() / 1000) - 120,
    content: JSON.stringify(content),
    tags: [
      ["d", d],
      ["p", OLYMPUS_OWNER],
      ["p", OLYMPUS_OPERATOR],
      ...extra,
      ["status", "active"],
    ],
    sig: "0".repeat(128),
  };
}

const ARGO_AGENT_FIELDS = [
  "spec.harness",
  "spec.instructionsFrom",
  "spec.mcpServers",
  "spec.model",
  "spec.pool",
  "spec.profile.displayName",
  "spec.skills",
];

const ARGO_SCHEDULE_FIELDS = [
  "spec.agent",
  "spec.asAgent",
  "spec.cron",
  "spec.script",
  "spec.timeZone",
  "spec.workspace",
];

export function olympusOpsWorkspaceEvent() {
  return state(30191, "ops", {
    v: 1,
    name: "ops",
    namespace: "olympus-ops",
    owner: OLYMPUS_OWNER,
    managedBy: "gitops",
    gitopsFields: [],
    spec: { suspend: false, quota: { cpu: "8", memory: "16Gi" } },
    status: {
      phase: "Ready",
      reason: null,
      channelId: "c0ffee00-0000-4000-8000-0000000000aa",
      schedulerPublicKey: OPS_SCHEDULER,
      mirrorPublicKey: null,
      conditions: [
        {
          type: "Ready",
          status: "True",
          reason: "Ready",
          message: "",
          lastTransitionTime: ago(900),
        },
      ],
    },
    providers: [
      {
        name: "claude",
        description: "Claude subscription through Hecate, flat rate",
        models: ["claude-opus-5-5", "claude-sonnet-5-5"],
        protocols: ["anthropic"],
      },
      { name: "codex", models: ["gpt-5.5"], protocols: ["openai"] },
    ],
    mcpServers: ["share", "hindsight", "github-mcp"],
    templates: [
      {
        name: "ops-base",
        namespace: "olympus",
        harness: "claude-code",
        pool: "claude",
        model: "claude-sonnet-5-5",
        effort: "high",
        mcpServers: ["share"],
        memory: { bank: "workspace" },
      },
    ],
  });
}

function agentSpec(extra: Record<string, unknown>) {
  return {
    template: null,
    harness: "claude-code",
    image: null,
    model: "claude-opus-5-5",
    effort: "high",
    pool: "claude",
    instructions: null,
    instructionsFrom: null,
    owner: null,
    storage: null,
    backup: false,
    resources: null,
    egress: [],
    identityPath: null,
    mcpServers: [],
    services: [],
    gitSources: [],
    skills: [],
    suspend: false,
    memory: null,
    respondTo: [],
    secrets: [],
    runtimeClass: null,
    kubernetesRole: null,
    profile: null,
    role: null,
    ...extra,
  };
}

function conditions(online: boolean) {
  return [
    {
      type: "Ready",
      status: "True",
      reason: "Available",
      message: "",
      lastTransitionTime: ago(600),
    },
    {
      type: "Online",
      status: online ? "True" : "False",
      reason: online ? "Connected" : "Suspended",
      message: "",
      lastTransitionTime: ago(5),
    },
  ];
}

export function olympusArgusEvent(input: { suspend?: boolean } = {}) {
  const suspend = input.suspend ?? false;
  return state(
    30190,
    "olympus-ops/argus",
    {
      v: 1,
      workspace: "ops",
      namespace: "olympus-ops",
      name: "argus",
      owner: OLYMPUS_OWNER,
      managedBy: "gitops",
      role: null,
      gitopsFields: ARGO_AGENT_FIELDS,
      spec: agentSpec({
        instructionsFrom: {
          skillsRepo: "agents",
          path: "argus/agents/argus.md",
        },
        mcpServers: [{ name: "share", tools: null }],
        skills: [{ repo: "agents", name: "observability" }],
        profile: {
          displayName: "Argus",
          picture: null,
          about: "Observability",
        },
        secrets: [{ name: "grafana-token", env: "GRAFANA_TOKEN" }],
        kubernetesRole: "cluster-reader",
        storage: "10Gi",
        backup: true,
        resources: { limits: { memory: "2Gi" }, requests: { cpu: "250m" } },
        egress: [
          { host: "api.github.com", cidr: null, preset: null, ports: [443] },
        ],
        memory: { bank: "workspace" },
        suspend,
      }),
      schedules: [
        {
          name: "daily-os-updates",
          cron: "30 6 * * *",
          timeZone: "Europe/Ljubljana",
          suspend: false,
          workspace: true,
          asAgent: true,
          prompt: null,
          script: { gitSource: "agents", path: "argus/jobs/os-updates.sh" },
          lastRunTime: ago(300),
          lastResult: "Failed",
          gitopsFields: ARGO_SCHEDULE_FIELDS,
        },
        {
          name: "argus-report",
          cron: "0 */4 * * *",
          timeZone: "Europe/Ljubljana",
          suspend: false,
          workspace: false,
          asAgent: false,
          prompt: "Post the observability report.",
          script: null,
          lastRunTime: ago(60),
          lastResult: "Succeeded",
          gitopsFields: [...ARGO_SCHEDULE_FIELDS, "spec.prompt"],
        },
      ],
      status: {
        phase: suspend ? "Suspended" : "Online",
        reason: suspend ? "Suspended" : null,
        publicKey: ARGUS_PUBLIC_KEY,
        lastActivity: ago(3),
        conditions: conditions(!suspend),
        template: null,
        egressMode: "hosts",
        egressProxy: true,
        backup: true,
        kubernetesRole: "cluster-reader",
      },
    },
    [["workspace", "ops"]],
  );
}

export function olympusZeusEvent() {
  return state(
    30190,
    "olympus-ops/zeus",
    {
      v: 1,
      workspace: "ops",
      namespace: "olympus-ops",
      name: "zeus",
      owner: OLYMPUS_OWNER,
      managedBy: "gitops",
      role: "master",
      gitopsFields: [...ARGO_AGENT_FIELDS, "spec.effort", "spec.role"],
      spec: agentSpec({
        role: "master",
        profile: { displayName: "Zeus", picture: null, about: null },
      }),
      schedules: [],
      status: {
        phase: "Online",
        reason: null,
        publicKey: ZEUS_PUBLIC_KEY,
        lastActivity: ago(1),
        conditions: conditions(true),
        template: null,
        egressMode: "none",
        egressProxy: false,
        backup: false,
        kubernetesRole: null,
      },
    },
    [["workspace", "ops"]],
  );
}

export function olympusOpsEvents() {
  return [olympusOpsWorkspaceEvent(), olympusArgusEvent(), olympusZeusEvent()];
}

export function olympusOpsResult(input: {
  requestId: string;
  status: "accepted" | "refused";
  reason: string;
  action: string;
  agent?: string;
  schedule?: string;
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
      ["workspace", "ops"],
      ...(input.agent ? [["agent", input.agent]] : []),
      ...(input.schedule ? [["schedule", input.schedule]] : []),
    ],
    sig: "0".repeat(128),
  };
}
