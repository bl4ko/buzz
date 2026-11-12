import type { RelayEvent } from "@/shared/api/types";
import {
  KIND_OLYMPUS_AGENT,
  KIND_OLYMPUS_WORKSPACE,
} from "@/shared/constants/kinds";

export const OLYMPUS_STATE_KINDS = [
  KIND_OLYMPUS_AGENT,
  KIND_OLYMPUS_WORKSPACE,
] as const;

export const OLYMPUS_PHASES = [
  "Pending",
  "Enrolled",
  "Ready",
  "Online",
  "Suspended",
] as const;
export type OlympusPhase = (typeof OLYMPUS_PHASES)[number];

export const OLYMPUS_EFFORTS = [
  "low",
  "medium",
  "high",
  "xhigh",
  "max",
] as const;

export const OLYMPUS_HARNESSES = ["claude-code", "codex"] as const;

export type OlympusCondition = {
  type: string;
  status: string;
  reason: string | null;
  message: string | null;
  lastTransitionTime: string | null;
};

export type OlympusMcpServer = { name: string; tools: string[] | null };
export type OlympusEgressRule = {
  host: string | null;
  cidr: string | null;
  preset: string | null;
  ports: number[];
};

export type OlympusAgentSpec = {
  harness: string;
  model: string;
  effort: string | null;
  pool: string;
  instructions: string | null;
  owner: string | null;
  suspend: boolean;
  mcpServers: OlympusMcpServer[];
  services: string[];
  memory: { bank: string } | null;
  gitSources: { name: string; access: string }[];
  skills: { repo: string; name: string }[];
  egress: OlympusEgressRule[];
};

export type OlympusSchedule = {
  name: string;
  cron: string | null;
  timeZone: string | null;
  suspend: boolean;
  workspace: boolean;
  prompt: string | null;
  script: string | null;
  lastRunTime: string | null;
  lastResult: string | null;
  truncated: boolean;
};

export type OlympusAgent = {
  author: string;
  eventId: string;
  createdAt: number;
  d: string;
  workspace: string;
  namespace: string;
  name: string;
  owner: string | null;
  managedBy: string | null;
  spec: OlympusAgentSpec;
  instructionsTruncated: boolean;
  schedules: OlympusSchedule[];
  phase: OlympusPhase;
  reason: string | null;
  publicKey: string | null;
  lastActivity: string | null;
  conditions: OlympusCondition[];
};

export type OlympusProvider = {
  name: string;
  models: string[];
  protocols: string[];
};

export type OlympusWorkspace = {
  author: string;
  eventId: string;
  createdAt: number;
  d: string;
  name: string;
  namespace: string;
  owner: string | null;
  managedBy: string | null;
  suspend: boolean;
  phase: string;
  reason: string | null;
  conditions: OlympusCondition[];
  providers: OlympusProvider[];
  mcpServers: string[];
};

export type OlympusWorkspaceGroup = {
  key: string;
  name: string;
  author: string;
  workspace: OlympusWorkspace | null;
  agents: OlympusAgent[];
};

type Json = Record<string, unknown>;

const HEX_KEY = /^[0-9a-f]{64}$/;

function isObject(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function text(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function texts(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

function objects(value: unknown): Json[] {
  return Array.isArray(value) ? value.filter(isObject) : [];
}

function singleTag(event: RelayEvent, name: string): string | null {
  const values = event.tags.filter((tag) => tag[0] === name);
  return values.length === 1 && typeof values[0][1] === "string"
    ? values[0][1]
    : null;
}

function olympusStateKey(event: RelayEvent, d: string) {
  return `${event.kind}:${event.pubkey}:${d}`;
}

function stateShape(event: RelayEvent) {
  if (!(OLYMPUS_STATE_KINDS as readonly number[]).includes(event.kind)) {
    return null;
  }
  const d = singleTag(event, "d");
  const status = singleTag(event, "status");
  if (!d || (status !== "active" && status !== "deleted")) return null;
  return { d, status };
}

function isNewer(candidate: RelayEvent, current: RelayEvent) {
  return (
    candidate.created_at > current.created_at ||
    (candidate.created_at === current.created_at && candidate.id < current.id)
  );
}

export function mergeOlympusEvents(
  current: readonly RelayEvent[],
  incoming: readonly RelayEvent[],
): RelayEvent[] {
  const newest = new Map<string, RelayEvent>();
  for (const event of [...current, ...incoming]) {
    const shape = stateShape(event);
    if (!shape) continue;
    const key = olympusStateKey(event, shape.d);
    const existing = newest.get(key);
    if (!existing || isNewer(event, existing)) newest.set(key, event);
  }
  return [...newest.values()];
}

function parseContent(event: RelayEvent): Json | null {
  try {
    const content: unknown = JSON.parse(event.content);
    return isObject(content) && content.v === 1 ? content : null;
  } catch {
    return null;
  }
}

function parseConditions(value: unknown): OlympusCondition[] {
  return objects(value).flatMap((condition) => {
    const type = text(condition.type);
    const status = text(condition.status);
    return type && status
      ? [
          {
            type,
            status,
            reason: text(condition.reason),
            message: text(condition.message),
            lastTransitionTime: text(condition.lastTransitionTime),
          },
        ]
      : [];
  });
}

function parseSpec(value: unknown): OlympusAgentSpec | null {
  if (!isObject(value)) return null;
  const harness = text(value.harness);
  const model = text(value.model);
  const pool = text(value.pool);
  if (!harness || !model || !pool) return null;
  const memory = isObject(value.memory) ? text(value.memory.bank) : null;
  return {
    harness,
    model,
    pool,
    effort: text(value.effort),
    instructions: text(value.instructions),
    owner: text(value.owner),
    suspend: value.suspend === true,
    mcpServers: objects(value.mcpServers).flatMap((server) => {
      const name = text(server.name);
      return name
        ? [
            {
              name,
              tools: Array.isArray(server.tools) ? texts(server.tools) : null,
            },
          ]
        : [];
    }),
    services: texts(value.services),
    memory: isObject(value.memory) ? { bank: memory ?? "private" } : null,
    gitSources: objects(value.gitSources).flatMap((source) => {
      const name = text(source.name);
      return name ? [{ name, access: text(source.access) ?? "read" }] : [];
    }),
    skills: objects(value.skills).flatMap((skill) => {
      const repo = text(skill.repo);
      const name = text(skill.name);
      return repo && name ? [{ repo, name }] : [];
    }),
    egress: objects(value.egress).map((rule) => ({
      host: text(rule.host),
      cidr: text(rule.cidr),
      preset: text(rule.preset),
      ports: Array.isArray(rule.ports)
        ? rule.ports.filter((port): port is number => Number.isInteger(port))
        : [],
    })),
  };
}

function parseSchedules(value: unknown): OlympusSchedule[] {
  return objects(value).flatMap((schedule) => {
    const name = text(schedule.name);
    if (!name) return [];
    const script = isObject(schedule.script)
      ? (text(schedule.script.inline) ??
        (Object.keys(schedule.script).length > 0 ? "external script" : null))
      : null;
    return [
      {
        name,
        cron: text(schedule.cron),
        timeZone: text(schedule.timeZone),
        suspend: schedule.suspend === true,
        workspace: schedule.workspace === true,
        prompt: text(schedule.prompt),
        script,
        lastRunTime: text(schedule.lastRunTime),
        lastResult: text(schedule.lastResult),
        truncated: schedule.truncated === true,
      },
    ];
  });
}

function hexOrNull(value: unknown) {
  const candidate = text(value)?.toLowerCase() ?? null;
  return candidate && HEX_KEY.test(candidate) ? candidate : null;
}

export function parseOlympusAgent(event: RelayEvent): OlympusAgent | null {
  const shape = stateShape(event);
  if (event.kind !== KIND_OLYMPUS_AGENT || shape?.status !== "active") {
    return null;
  }
  const content = parseContent(event);
  if (!content) return null;
  const name = text(content.name);
  const workspace = text(content.workspace);
  const spec = parseSpec(content.spec);
  const status = isObject(content.status) ? content.status : null;
  const phase = status ? text(status.phase) : null;
  if (
    !name ||
    !workspace ||
    !spec ||
    !phase ||
    !(OLYMPUS_PHASES as readonly string[]).includes(phase)
  ) {
    return null;
  }
  return {
    author: event.pubkey,
    eventId: event.id,
    createdAt: event.created_at,
    d: shape.d,
    workspace,
    namespace: text(content.namespace) ?? "",
    name,
    owner: hexOrNull(content.owner),
    managedBy: text(content.managedBy),
    spec,
    instructionsTruncated: content.instructionsTruncated === true,
    schedules: parseSchedules(content.schedules),
    phase: phase as OlympusPhase,
    reason: text(status?.reason),
    publicKey: hexOrNull(status?.publicKey),
    lastActivity: text(status?.lastActivity),
    conditions: parseConditions(status?.conditions),
  };
}

export function parseOlympusWorkspace(
  event: RelayEvent,
): OlympusWorkspace | null {
  const shape = stateShape(event);
  if (event.kind !== KIND_OLYMPUS_WORKSPACE || shape?.status !== "active") {
    return null;
  }
  const content = parseContent(event);
  const name = content ? text(content.name) : null;
  if (!content || !name) return null;
  const spec = isObject(content.spec) ? content.spec : {};
  const status = isObject(content.status) ? content.status : {};
  return {
    author: event.pubkey,
    eventId: event.id,
    createdAt: event.created_at,
    d: shape.d,
    name,
    namespace: text(content.namespace) ?? "",
    owner: hexOrNull(content.owner),
    managedBy: text(content.managedBy),
    suspend: spec.suspend === true,
    phase: text(status.phase) ?? "Pending",
    reason: text(status.reason),
    conditions: parseConditions(status.conditions),
    providers: objects(content.providers).flatMap((provider) => {
      const providerName = text(provider.name);
      return providerName
        ? [
            {
              name: providerName,
              models: texts(provider.models),
              protocols: texts(provider.protocols),
            },
          ]
        : [];
    }),
    mcpServers: texts(content.mcpServers),
  };
}

function byName<T extends { name: string }>(left: T, right: T) {
  return left.name.localeCompare(right.name);
}

export function groupOlympusAgents(
  events: readonly RelayEvent[],
): OlympusWorkspaceGroup[] {
  const groups = new Map<string, OlympusWorkspaceGroup>();
  const groupFor = (author: string, name: string) => {
    const key = `${author}:${name}`;
    let group = groups.get(key);
    if (!group) {
      group = { key, name, author, workspace: null, agents: [] };
      groups.set(key, group);
    }
    return group;
  };
  const newest = mergeOlympusEvents([], events);
  for (const event of newest) {
    const workspace = parseOlympusWorkspace(event);
    if (workspace)
      groupFor(workspace.author, workspace.name).workspace = workspace;
  }
  for (const event of newest) {
    const agent = parseOlympusAgent(event);
    if (agent) groupFor(agent.author, agent.workspace).agents.push(agent);
  }
  const result = [...groups.values()].sort(byName);
  for (const group of result) group.agents.sort(byName);
  return result;
}

export function findOlympusAgent(
  groups: readonly OlympusWorkspaceGroup[],
  author: string,
  d: string,
): OlympusAgent | null {
  for (const group of groups) {
    const agent = group.agents.find(
      (candidate) => candidate.author === author && candidate.d === d,
    );
    if (agent) return agent;
  }
  return null;
}

export function olympusModelOptions(
  workspace: OlympusWorkspace | null,
  pool: string,
): string[] {
  return (
    workspace?.providers.find((provider) => provider.name === pool)?.models ??
    []
  );
}

export function olympusAddableMcpServers(
  workspace: OlympusWorkspace | null,
  agent: OlympusAgent,
): string[] {
  const present = new Set(agent.spec.mcpServers.map((server) => server.name));
  return (workspace?.mcpServers ?? []).filter(
    (name) => name !== "hindsight" && !present.has(name),
  );
}

export const OLYMPUS_AGENT_NAME_PATTERN =
  /^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$/;
