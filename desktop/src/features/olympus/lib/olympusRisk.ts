type Json = Record<string, unknown>;

export const OLYMPUS_RISK_FIELDS = [
  "kubernetesRole",
  "secrets",
  "runtimeClass",
  "owner",
  "identityPath",
  "role",
] as const;

const LABELS: Record<string, string> = {
  kubernetesRole: "Kubernetes role",
  secrets: "secrets",
  runtimeClass: "runtime class",
  owner: "owner",
  identityPath: "identity path",
  role: "agent role",
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

export function olympusAgentRisks(
  before: Json | null,
  after: Json,
  input: { master: boolean },
): string[] {
  const risks: string[] = OLYMPUS_RISK_FIELDS.filter(
    (field) =>
      !same(before?.[field], after[field]) &&
      (before?.[field] != null || after[field] != null),
  );
  if (openEgress(after) && !openEgress(before)) risks.push("egress open");
  if (input.master) risks.push("master agent");
  return risks;
}

export function olympusRiskLabel(risk: string): string {
  return LABELS[risk] ?? risk;
}
