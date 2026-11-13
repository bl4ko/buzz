type Json = Record<string, unknown>;

export const OLYMPUS_RISK_FIELDS = [
  "kubernetesRole",
  "secrets",
  "runtimeClass",
  "owner",
  "identityPath",
  "role",
  "template",
  "respondTo",
  "image",
] as const;

const LABELS: Record<string, string> = {
  kubernetesRole: "Kubernetes role",
  secrets: "secrets",
  runtimeClass: "runtime class",
  owner: "owner",
  identityPath: "identity path",
  role: "agent role",
  template: "agent template",
  respondTo: "who the agent answers",
  image: "container image",
  "egress direct": "direct network egress",
  "git write": "git write access",
  "mcpServers credential": "a new MCP server (it can carry a credential)",
  "services credential": "a new service (it can carry a credential)",
  "egress open": "open internet egress",
  "master agent": "the master agent",
  "master workspace": "the workspace of the master agent",
};

function same(left: unknown, right: unknown) {
  return JSON.stringify(left ?? null) === JSON.stringify(right ?? null);
}

function openEgress(spec: Json | null) {
  const rules = spec?.egress;
  return (
    Array.isArray(rules) &&
    rules.some(
      (rule) =>
        typeof rule === "object" && rule !== null && rule.preset === "internet",
    )
  );
}

export function olympusMergePatch(target: Json, patch: Json): Json {
  const result: Json = { ...target };
  for (const [key, value] of Object.entries(patch)) {
    if (value === null) delete result[key];
    else if (
      typeof value === "object" &&
      !Array.isArray(value) &&
      typeof result[key] === "object" &&
      result[key] !== null &&
      !Array.isArray(result[key])
    ) {
      result[key] = olympusMergePatch(result[key] as Json, value as Json);
    } else result[key] = value;
  }
  return result;
}

function plain(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function olympusSpecPatch(before: Json, after: Json): Json {
  const patch: Json = {};
  for (const key of new Set([...Object.keys(before), ...Object.keys(after)])) {
    const previous = before[key];
    const next = after[key];
    if (same(previous, next)) continue;
    if (next === undefined || next === null) {
      if (previous !== undefined && previous !== null) patch[key] = null;
    } else if (plain(previous) && plain(next)) {
      const nested = olympusSpecPatch(previous, next);
      if (Object.keys(nested).length > 0) patch[key] = nested;
    } else patch[key] = next;
  }
  return patch;
}

export function olympusWithoutNulls(value: Json): Json {
  const result: Json = {};
  for (const [key, item] of Object.entries(value)) {
    if (item === null || item === undefined) continue;
    result[key] = plain(item) ? olympusWithoutNulls(item) : item;
  }
  return result;
}

function entries(spec: Json | null, field: string): unknown[] {
  const value = spec?.[field];
  return Array.isArray(value) ? value : [];
}

function added(before: Json | null, after: Json, field: string) {
  const held = entries(before, field).map((entry) => JSON.stringify(entry));
  return entries(after, field).filter(
    (entry) => !held.includes(JSON.stringify(entry)),
  );
}

function rank(access: unknown) {
  return access === "admin" ? 2 : access === "write" ? 1 : 0;
}

export function olympusAgentRisks(
  before: Json | null,
  after: Json,
  input: { master: boolean },
): string[] {
  const risks: string[] = OLYMPUS_RISK_FIELDS.filter(
    (field) => !same(before?.[field], after[field]),
  );
  if (openEgress(after) && !openEgress(before)) risks.push("egress open");
  if (
    added(before, after, "egress").some(
      (rule) => plain(rule) && (rule.cidr != null || rule.preset === "cluster"),
    )
  ) {
    risks.push("egress direct");
  }
  const writes = entries(after, "gitSources").some(
    (wanted) =>
      plain(wanted) &&
      rank(wanted.access) > 0 &&
      !entries(before, "gitSources").some(
        (held) =>
          plain(held) &&
          held.name === wanted.name &&
          rank(held.access) >= rank(wanted.access),
      ),
  );
  if (writes) risks.push("git write");
  for (const field of ["mcpServers", "services"]) {
    if (added(before, after, field).length > 0) {
      risks.push(`${field} credential`);
    }
  }
  if (input.master) risks.push("master agent");
  return risks;
}

export function olympusRiskLabel(risk: string): string {
  return LABELS[risk] ?? risk;
}
