import * as React from "react";

import type { RelayEvent } from "@/shared/api/types";
import {
  KIND_OLYMPUS_CHANGE_REQUEST,
  KIND_OLYMPUS_CHANGE_RESULT,
} from "@/shared/constants/kinds";
import type { RelaySubscriptionFilter } from "@/shared/api/relayClientShared";

export const OLYMPUS_RESULT_TIMEOUT_MS = 30_000;

export type OlympusChange =
  | { action: "suspend" | "resume" | "delete" }
  | {
      action: "update";
      model?: string;
      effort?: string | null;
      instructions?: string | null;
    }
  | { action: "add-mcp"; server: { name: string; tools?: string[] } }
  | { action: "remove-mcp"; server: string }
  | { action: "set-memory"; memory: { bank: "private" | "workspace" } | null }
  | {
      action: "create";
      harness: string;
      pool: string;
      model: string;
      effort?: string;
      instructions?: string;
    }
  | { action: "create"; spec: Record<string, unknown>; highRisk?: true }
  | { action: "patch"; patch: Record<string, unknown>; highRisk?: true }
  | { action: "suspend-schedule" | "resume-schedule" | "run-now" }
  | {
      action: "approve" | "reject";
      proposal: string;
      digest: string;
      highRisk?: true;
      reason?: string;
    };

export type OlympusChangeTarget = {
  operator: string;
  workspace: string;
  agent: string | null;
  schedule?: string | null;
};

export type OlympusEventTemplate = {
  kind: number;
  content: string;
  tags: string[][];
};

const WORKSPACE_ACTIONS = new Set(["suspend", "resume", "patch"]);
const SCHEDULE_ACTIONS = new Set([
  "suspend-schedule",
  "resume-schedule",
  "run-now",
  "patch",
]);

export function buildOlympusChangeRequest(
  target: OlympusChangeTarget,
  change: OlympusChange,
): OlympusEventTemplate {
  if (!/^[0-9a-f]{64}$/.test(target.operator)) {
    throw new Error("The operator key is not valid.");
  }
  if (!target.workspace) throw new Error("The workspace is missing.");
  const isProposal = "proposal" in change;
  if (isProposal && target.agent) {
    throw new Error(`The ${change.action} action has no agent.`);
  }
  const schedule = target.schedule ?? null;
  if (schedule && (target.agent || !SCHEDULE_ACTIONS.has(change.action))) {
    throw new Error(`The ${change.action} action has no schedule.`);
  }
  if (!schedule && change.action.endsWith("-schedule")) {
    throw new Error(`The ${change.action} action needs a schedule.`);
  }
  if (!schedule && change.action === "run-now") {
    throw new Error("The run-now action needs a schedule.");
  }
  if (
    !target.agent &&
    !schedule &&
    !WORKSPACE_ACTIONS.has(change.action) &&
    !isProposal
  ) {
    throw new Error(`The ${change.action} action needs an agent.`);
  }
  if (
    isProposal &&
    (!change.proposal || !/^[0-9a-f]{64}$/.test(change.digest))
  ) {
    throw new Error("The proposal name or digest is not valid.");
  }
  const tags = [
    ["p", target.operator],
    ["workspace", target.workspace],
  ];
  if (target.agent) tags.push(["agent", target.agent]);
  if (schedule) tags.push(["schedule", schedule]);
  tags.push(["action", change.action]);
  if (isProposal) tags.push(["proposal", change.proposal]);
  const { action, ...params } = change;
  const content = {
    v: 1,
    action,
    workspace: target.workspace,
    ...(target.agent ? { agent: target.agent } : {}),
    ...(schedule ? { schedule } : {}),
    ...params,
  };
  return {
    kind: KIND_OLYMPUS_CHANGE_REQUEST,
    content: JSON.stringify(content),
    tags,
  };
}

export type OlympusChangeResult = {
  status: "accepted" | "refused";
  reason: string | null;
};

export function parseOlympusChangeResult(
  event: RelayEvent,
  requestId: string,
  operator: string,
): OlympusChangeResult | null {
  if (event.kind !== KIND_OLYMPUS_CHANGE_RESULT || event.pubkey !== operator) {
    return null;
  }
  const eTags = event.tags.filter((tag) => tag[0] === "e");
  if (eTags.length !== 1 || eTags[0][1] !== requestId) return null;
  const statusTags = event.tags.filter((tag) => tag[0] === "status");
  const status = statusTags.length === 1 ? statusTags[0][1] : null;
  if (status !== "accepted" && status !== "refused") return null;
  let reason: string | null = null;
  try {
    const content: unknown = JSON.parse(event.content);
    if (
      typeof content === "object" &&
      content !== null &&
      "reason" in content &&
      typeof content.reason === "string" &&
      content.reason.length > 0
    ) {
      reason = content.reason;
    }
  } catch {}
  return { status, reason };
}

export type OlympusRequestState =
  | { phase: "pending"; action: string }
  | { phase: "accepted" | "refused"; action: string; reason: string | null }
  | { phase: "failed"; action: string; reason: string };

export type OlympusChangeTransport = {
  sign: (template: OlympusEventTemplate) => Promise<RelayEvent>;
  subscribe: (
    filter: RelaySubscriptionFilter,
    onEvent: (event: RelayEvent) => void,
  ) => Promise<() => Promise<void>>;
  publish: (event: RelayEvent) => Promise<unknown>;
};

const states = new Map<string, OlympusRequestState>();
const listeners = new Set<() => void>();
const cleanups = new Set<() => void>();
let generation = 0;
let version = 0;

function setState(key: string, state: OlympusRequestState | null) {
  if (state) states.set(key, state);
  else states.delete(key);
  version += 1;
  for (const listener of listeners) listener();
}

export function olympusRequestKey(workspace: string, agent: string | null) {
  return agent ? `${workspace}/${agent}` : workspace;
}

export function olympusScheduleRequestKey(workspace: string, schedule: string) {
  return `${workspace}#schedule/${schedule}`;
}

export function getOlympusRequestState(key: string) {
  return states.get(key) ?? null;
}

export function clearOlympusRequestState(key: string) {
  if (states.get(key)?.phase !== "pending") setState(key, null);
}

export function resetOlympusChangeRequests() {
  generation += 1;
  for (const cleanup of cleanups) cleanup();
  cleanups.clear();
  states.clear();
  version += 1;
  for (const listener of listeners) listener();
}

function errorText(error: unknown) {
  return error instanceof Error && error.message
    ? error.message
    : "The change request failed.";
}

export async function submitOlympusChange(
  input: {
    key: string;
    me: string;
    target: OlympusChangeTarget;
    change: OlympusChange;
    timeoutMs?: number;
  },
  transport: OlympusChangeTransport,
): Promise<OlympusRequestState | null> {
  const { key, me, target, change } = input;
  if (states.get(key)?.phase === "pending") return null;
  const startedIn = generation;
  const isCurrent = () => startedIn === generation;
  setState(key, { phase: "pending", action: change.action });

  let dispose: (() => Promise<void>) | null = null;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let settle: (state: OlympusRequestState) => void = () => {};
  const settled = new Promise<OlympusRequestState>((resolve) => {
    settle = resolve;
  });
  const cleanup = () => {
    clearTimeout(timer);
    if (dispose) void dispose().catch(() => {});
    dispose = null;
    settle({ phase: "failed", action: change.action, reason: "Cancelled." });
  };
  cleanups.add(cleanup);

  try {
    const event = await transport.sign(
      buildOlympusChangeRequest(target, change),
    );
    if (!isCurrent()) return null;
    dispose = await transport.subscribe(
      {
        kinds: [KIND_OLYMPUS_CHANGE_RESULT],
        "#e": [event.id],
        "#p": [me],
        limit: 1,
      },
      (candidate) => {
        const result = parseOlympusChangeResult(
          candidate,
          event.id,
          target.operator,
        );
        if (result) {
          settle({
            phase: result.status,
            action: change.action,
            reason: result.reason,
          });
        }
      },
    );
    if (!isCurrent()) {
      cleanup();
      return null;
    }
    timer = setTimeout(
      () =>
        settle({
          phase: "failed",
          action: change.action,
          reason:
            "No answer from Hephaestus in 30 seconds. The change can still apply later.",
        }),
      input.timeoutMs ?? OLYMPUS_RESULT_TIMEOUT_MS,
    );
    await transport.publish(event);
    const state = await settled;
    if (!isCurrent()) return null;
    setState(key, state);
    return state;
  } catch (error) {
    if (!isCurrent()) return null;
    const state: OlympusRequestState = {
      phase: "failed",
      action: change.action,
      reason: errorText(error),
    };
    setState(key, state);
    return state;
  } finally {
    cleanup();
    cleanups.delete(cleanup);
  }
}

function subscribeStates(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

export function useOlympusRequestState(key: string) {
  return React.useSyncExternalStore(
    subscribeStates,
    () => getOlympusRequestState(key),
    () => null,
  );
}

export function useOlympusRequestVersion() {
  return React.useSyncExternalStore(
    subscribeStates,
    () => version,
    () => 0,
  );
}
