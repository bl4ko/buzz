import type { RelayEvent } from "@/shared/api/types";
import {
  KIND_OLYMPUS_AGENT,
  KIND_OLYMPUS_PROPOSAL,
  KIND_OLYMPUS_WORKSPACE,
} from "@/shared/constants/kinds";

export const OLYMPUS_STATE_KINDS = [
  KIND_OLYMPUS_AGENT,
  KIND_OLYMPUS_WORKSPACE,
  KIND_OLYMPUS_PROPOSAL,
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

export type OlympusSecretRef = { name: string; env: string | null };

export type OlympusAgentSpec = {
  template: string | null;
  harness: string;
  image: string | null;
  model: string;
  effort: string | null;
  pool: string;
  instructions: string | null;
  instructionsFrom: { skillsRepo: string; path: string } | null;
  owner: string | null;
  storage: string | null;
  backup: boolean;
  resources: Record<string, Record<string, string>> | null;
  suspend: boolean;
  mcpServers: OlympusMcpServer[];
  services: string[];
  memory: { bank: string } | null;
  gitSources: { name: string; access: string }[];
  skills: { repo: string; name: string }[];
  egress: OlympusEgressRule[];
  respondTo: string[];
  secrets: OlympusSecretRef[];
  runtimeClass: string | null;
  kubernetesRole: string | null;
  identityPath: string | null;
  role: string | null;
  profile: {
    displayName: string | null;
    picture: string | null;
    about: string | null;
  } | null;
};

export type OlympusSchedule = {
  name: string;
  cron: string | null;
  timeZone: string | null;
  suspend: boolean;
  workspace: boolean;
  asAgent: boolean;
  prompt: string | null;
  script: string | null;
  scriptSource: { gitSource: string; path: string | null } | null;
  lastRunTime: string | null;
  lastResult: string | null;
  truncated: boolean;
  gitopsFields: string[] | null;
};

export type OlympusAgentRuntime = {
  template: { name: string; namespace: string | null } | null;
  egressMode: string | null;
  egressProxy: boolean;
  backup: boolean;
  kubernetesRole: string | null;
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
  role: string | null;
  spec: OlympusAgentSpec;
  effectiveSpec: OlympusAgentSpec | null;
  rawSpec: Record<string, unknown>;
  gitopsFields: string[] | null;
  runtime: OlympusAgentRuntime;
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

export type OlympusTemplate = {
  name: string;
  namespace: string | null;
  harness: string | null;
  pool: string | null;
  model: string | null;
  effort: string | null;
  mcpServers: string[];
  memory: { bank: string } | null;
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
  quota: Record<string, string> | null;
  phase: string;
  reason: string | null;
  channelId: string | null;
  schedulerPublicKey: string | null;
  conditions: OlympusCondition[];
  providers: OlympusProvider[];
  mcpServers: string[];
  templates: OlympusTemplate[];
  gitopsFields: string[] | null;
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

function stringMap(value: unknown): Record<string, string> | null {
  if (!isObject(value)) return null;
  const entries = Object.entries(value).flatMap(([key, item]) =>
    typeof item === "string" || typeof item === "number"
      ? [[key, String(item)] as const]
      : [],
  );
  return entries.length > 0 ? Object.fromEntries(entries) : null;
}

function parseResources(value: unknown) {
  if (!isObject(value)) return null;
  const result: Record<string, Record<string, string>> = {};
  for (const key of ["requests", "limits"]) {
    const map = stringMap(value[key]);
    if (map) result[key] = map;
  }
  return Object.keys(result).length > 0 ? result : null;
}

function parseSpec(value: unknown): OlympusAgentSpec | null {
  if (!isObject(value)) return null;
  const template = text(value.template);
  const harness = text(value.harness);
  const model = text(value.model);
  const pool = text(value.pool);
  if ((!harness || !model || !pool) && !template) return null;
  const memory = isObject(value.memory) ? text(value.memory.bank) : null;
  const from = isObject(value.instructionsFrom) ? value.instructionsFrom : null;
  const skillsRepo = from ? text(from.skillsRepo) : null;
  const storage = value.storage;
  return {
    template,
    harness: harness ?? "",
    image: text(value.image),
    model: model ?? "",
    pool: pool ?? "",
    effort: text(value.effort),
    instructions: text(value.instructions),
    instructionsFrom:
      from && skillsRepo ? { skillsRepo, path: text(from.path) ?? "" } : null,
    owner: text(value.owner),
    storage:
      typeof storage === "number" ? String(storage) : (text(storage) ?? null),
    backup: value.backup === true,
    resources: parseResources(value.resources),
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
    respondTo: texts(value.respondTo),
    secrets: objects(value.secrets).flatMap((secret) => {
      const name = text(secret.name);
      return name ? [{ name, env: text(secret.env) }] : [];
    }),
    runtimeClass: text(value.runtimeClass),
    kubernetesRole: text(value.kubernetesRole),
    identityPath: text(value.identityPath),
    role: text(value.role),
    profile: isObject(value.profile)
      ? {
          displayName: text(value.profile.displayName),
          picture: text(value.profile.picture),
          about: text(value.profile.about),
        }
      : null,
  };
}

function fieldList(value: unknown): string[] | null {
  return Array.isArray(value) ? texts(value) : null;
}

function parseSchedules(value: unknown): OlympusSchedule[] {
  return objects(value).flatMap((schedule) => {
    const name = text(schedule.name);
    if (!name) return [];
    const script = isObject(schedule.script) ? schedule.script : null;
    const gitSource = script ? text(script.gitSource) : null;
    return [
      {
        name,
        cron: text(schedule.cron),
        timeZone: text(schedule.timeZone),
        suspend: schedule.suspend === true,
        workspace: schedule.workspace === true,
        asAgent: schedule.asAgent === true,
        prompt: text(schedule.prompt),
        script: script
          ? (text(script.inline) ??
            (gitSource
              ? `${gitSource}:${text(script.path) ?? ""}`
              : Object.keys(script).length > 0
                ? "external script"
                : null))
          : null,
        scriptSource: gitSource
          ? { gitSource, path: text(script?.path) }
          : null,
        lastRunTime: text(schedule.lastRunTime),
        lastResult: text(schedule.lastResult),
        truncated: schedule.truncated === true,
        gitopsFields: fieldList(schedule.gitopsFields),
      },
    ];
  });
}

function parseRuntime(status: Json | null): OlympusAgentRuntime {
  const template = status && isObject(status.template) ? status.template : null;
  const templateName = template ? text(template.name) : null;
  return {
    template: templateName
      ? { name: templateName, namespace: text(template?.namespace) }
      : null,
    egressMode: text(status?.egressMode),
    egressProxy: status?.egressProxy === true,
    backup: status?.backup === true,
    kubernetesRole: text(status?.kubernetesRole),
  };
}

function parseTemplates(value: unknown): OlympusTemplate[] {
  return objects(value).flatMap((template) => {
    const name = text(template.name);
    if (!name) return [];
    const memory = isObject(template.memory)
      ? text(template.memory.bank)
      : null;
    return [
      {
        name,
        namespace: text(template.namespace),
        harness: text(template.harness),
        pool: text(template.pool),
        model: text(template.model),
        effort: text(template.effort),
        mcpServers: texts(template.mcpServers),
        memory: memory ? { bank: memory } : null,
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
    role: text(content.role),
    spec,
    effectiveSpec: parseSpec(content.effectiveSpec),
    rawSpec: isObject(content.spec) ? content.spec : {},
    gitopsFields: fieldList(content.gitopsFields),
    runtime: parseRuntime(status),
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
    quota: stringMap(spec.quota),
    phase: text(status.phase) ?? "Pending",
    reason: text(status.reason),
    channelId: text(status.channelId),
    schedulerPublicKey: hexOrNull(status.schedulerPublicKey),
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
    templates: parseTemplates(content.templates),
    gitopsFields: fieldList(content.gitopsFields),
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

export function olympusEffectiveSpec(agent: OlympusAgent): OlympusAgentSpec {
  return agent.effectiveSpec ?? agent.spec;
}

export function olympusAgentLabel(agent: OlympusAgent): string {
  return agent.spec.profile?.displayName ?? agent.name;
}
