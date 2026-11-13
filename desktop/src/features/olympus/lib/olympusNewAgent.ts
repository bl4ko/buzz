import type {
  OlympusAgent,
  OlympusTemplate,
  OlympusWorkspace,
} from "@/features/agents/lib/olympusAgents";
import { olympusEffectiveSpec } from "@/features/agents/lib/olympusAgents";
import type { OlympusChange } from "@/features/agents/lib/olympusChangeRequests";
import { olympusAgentRisks, olympusWithoutNulls } from "./olympusRisk";

type Json = Record<string, unknown>;

export type OlympusStart =
  | { kind: "blank" }
  | { kind: "template"; template: OlympusTemplate }
  | { kind: "clone"; agent: OlympusAgent };

export type OlympusMemoryChoice = "" | "private" | "workspace";
export type OlympusEgressChoice = "" | "cluster" | "internet";

export type OlympusNewAgentDraft = {
  name: string;
  harness: string;
  pool: string;
  model: string;
  effort: string;
  displayName: string;
  instructions: string;
  mcpServers: string[];
  memory: OlympusMemoryChoice;
  egress: OlympusEgressChoice;
};

const PROTOCOLS: Record<string, string> = {
  "claude-code": "anthropic",
  codex: "openai",
};

const CLONE_DROPPED = ["identityPath", "owner", "role", "suspend", "profile"];

export function olympusPoolsFor(
  workspace: OlympusWorkspace | null,
  harness: string,
) {
  const protocol = PROTOCOLS[harness];
  return (workspace?.providers ?? []).filter(
    (provider) => !protocol || provider.protocols.includes(protocol),
  );
}

function egressChoice(rules: readonly { preset: string | null }[]) {
  if (rules.some((rule) => rule.preset === "internet")) return "internet";
  if (rules.some((rule) => rule.preset === "cluster")) return "cluster";
  return "";
}

function memoryChoice(memory: { bank: string } | null): OlympusMemoryChoice {
  if (!memory) return "";
  return memory.bank === "workspace" ? "workspace" : "private";
}

export function olympusStartDraft(
  start: OlympusStart,
  workspace: OlympusWorkspace | null,
): OlympusNewAgentDraft {
  if (start.kind === "clone") {
    const spec = olympusEffectiveSpec(start.agent);
    return {
      name: `${start.agent.name}-copy`.slice(0, 63),
      harness: spec.harness,
      pool: spec.pool,
      model: spec.model,
      effort: spec.effort ?? "",
      displayName: "",
      instructions: start.agent.spec.instructions ?? "",
      mcpServers: spec.mcpServers.map((server) => server.name),
      memory: memoryChoice(spec.memory),
      egress: egressChoice(spec.egress),
    };
  }
  if (start.kind === "template") {
    const { template } = start;
    return {
      name: "",
      harness: template.harness ?? "claude-code",
      pool: template.pool ?? "",
      model: template.model ?? "",
      effort: template.effort ?? "",
      displayName: "",
      instructions: "",
      mcpServers: [...template.mcpServers],
      memory: memoryChoice(template.memory),
      egress: "",
    };
  }
  const pool = olympusPoolsFor(workspace, "claude-code")[0];
  return {
    name: "",
    harness: "claude-code",
    pool: pool?.name ?? "",
    model: pool?.models[0] ?? "",
    effort: "",
    displayName: "",
    instructions: "",
    mcpServers: [],
    memory: "",
    egress: "",
  };
}

function sameList(left: readonly string[], right: readonly string[]) {
  return (
    left.length === right.length && left.every((item, i) => item === right[i])
  );
}

function egressRules(choice: OlympusEgressChoice, current: unknown) {
  const kept = Array.isArray(current)
    ? current.filter(
        (rule) =>
          typeof rule === "object" &&
          rule !== null &&
          (rule as Json).preset !== "internet" &&
          (rule as Json).preset !== "cluster",
      )
    : [];
  return choice ? [...kept, { preset: choice }] : kept;
}

export function olympusCreateSpec(
  start: OlympusStart,
  draft: OlympusNewAgentDraft,
): Json {
  const base: Json =
    start.kind === "clone"
      ? olympusWithoutNulls(start.agent.rawSpec)
      : start.kind === "template"
        ? { template: start.template.name }
        : {};
  for (const key of CLONE_DROPPED) delete base[key];
  for (const [key, value] of Object.entries(base)) {
    if ((Array.isArray(value) && value.length === 0) || value === false) {
      delete base[key];
    }
  }
  const spec: Json = { ...base };
  const template = start.kind === "template" ? start.template : null;
  const put = (key: string, value: string, inherited: string | null) => {
    if (value && value !== inherited) spec[key] = value;
    else if (!value || template) delete spec[key];
  };
  put("harness", draft.harness, template?.harness ?? null);
  put("pool", draft.pool, template?.pool ?? null);
  put("model", draft.model.trim(), template?.model ?? null);
  put("effort", draft.effort, template?.effort ?? null);
  if (draft.instructions.trim()) spec.instructions = draft.instructions;
  else delete spec.instructions;
  if (spec.instructionsFrom) delete spec.instructions;
  if (!template || !sameList(draft.mcpServers, template.mcpServers)) {
    const tools = new Map(
      (start.kind === "clone" ? start.agent.spec.mcpServers : []).map(
        (server) => [server.name, server.tools],
      ),
    );
    spec.mcpServers = draft.mcpServers.map((name) => {
      const list = tools.get(name);
      return list ? { name, tools: list } : { name };
    });
    if (draft.mcpServers.length === 0 && !template) delete spec.mcpServers;
  }
  const templateMemory = template ? memoryChoice(template.memory) : "";
  if (!template || draft.memory !== templateMemory) {
    spec.memory = draft.memory ? { bank: draft.memory } : null;
    if (!draft.memory && !template) delete spec.memory;
  }
  const egress = egressRules(draft.egress, spec.egress);
  if (egress.length > 0) spec.egress = egress;
  else delete spec.egress;
  if (draft.displayName.trim()) {
    spec.profile = { displayName: draft.displayName.trim() };
  }
  return spec;
}

export function olympusCreateChange(
  start: OlympusStart,
  draft: OlympusNewAgentDraft,
  legacy: boolean,
): { change: OlympusChange; risks: string[] } {
  if (legacy) {
    return {
      change: {
        action: "create",
        harness: draft.harness,
        pool: draft.pool,
        model: draft.model.trim(),
        ...(draft.effort ? { effort: draft.effort } : {}),
        ...(draft.instructions.trim()
          ? { instructions: draft.instructions }
          : {}),
      },
      risks: [],
    };
  }
  const spec = olympusCreateSpec(start, draft);
  return {
    change: { action: "create", spec },
    risks: olympusAgentRisks(null, spec, { master: false }),
  };
}
