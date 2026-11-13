import {
  isOlympusProposalOpen,
  type OlympusProposal,
  olympusProposalKey,
} from "@/features/agents/lib/olympusProposals";

export const PROPOSAL_SOON_SECONDS = 2 * 3_600;
const LEDGER_LIMIT = 500;
const STORAGE_PREFIX = "buzz.olympus.proposal-alerts.v1:";

export type ProposalAlertLedger = { new: string[]; soon: string[] };
export type ProposalAlertKind = keyof ProposalAlertLedger;
export type ProposalAlert = {
  kind: ProposalAlertKind;
  proposal: OlympusProposal;
};

export const EMPTY_PROPOSAL_ALERT_LEDGER: ProposalAlertLedger = {
  new: [],
  soon: [],
};

export function planProposalAlerts(
  proposals: readonly OlympusProposal[],
  nowSeconds: number,
  ledger: ProposalAlertLedger,
): { alerts: ProposalAlert[]; nextCheckAt: number | null } {
  const announced = new Set(ledger.new);
  const warned = new Set(ledger.soon);
  const alerts: ProposalAlert[] = [];
  let nextCheckAt: number | null = null;
  for (const proposal of proposals) {
    if (!isOlympusProposalOpen(proposal, nowSeconds)) continue;
    const key = olympusProposalKey(proposal);
    const soonAt = proposal.expiresAt - PROPOSAL_SOON_SECONDS;
    const soon = nowSeconds >= soonAt;
    if (!announced.has(key)) {
      alerts.push({ kind: "new", proposal });
    } else if (soon && !warned.has(key)) {
      alerts.push({ kind: "soon", proposal });
    }
    if (!soon && !warned.has(key)) {
      nextCheckAt =
        nextCheckAt === null ? soonAt : Math.min(nextCheckAt, soonAt);
    }
  }
  return { alerts, nextCheckAt };
}

export function recordProposalAlert(
  ledger: ProposalAlertLedger,
  alert: ProposalAlert,
  nowSeconds: number,
): ProposalAlertLedger {
  const key = olympusProposalKey(alert.proposal);
  const add = (list: string[]) =>
    list.includes(key) ? list : [...list, key].slice(-LEDGER_LIMIT);
  const soon =
    alert.kind === "soon" ||
    nowSeconds >= alert.proposal.expiresAt - PROPOSAL_SOON_SECONDS;
  return {
    new: add(ledger.new),
    soon: soon ? add(ledger.soon) : ledger.soon,
  };
}

function texts(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

export function loadProposalAlertLedger(
  storage: Pick<Storage, "getItem"> | null,
  pubkey: string,
): ProposalAlertLedger {
  try {
    const raw = storage?.getItem(`${STORAGE_PREFIX}${pubkey}`);
    if (!raw) return EMPTY_PROPOSAL_ALERT_LEDGER;
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed !== "object" || parsed === null) {
      return EMPTY_PROPOSAL_ALERT_LEDGER;
    }
    const value = parsed as Record<string, unknown>;
    return { new: texts(value.new), soon: texts(value.soon) };
  } catch {
    return EMPTY_PROPOSAL_ALERT_LEDGER;
  }
}

export function saveProposalAlertLedger(
  storage: Pick<Storage, "setItem"> | null,
  pubkey: string,
  ledger: ProposalAlertLedger,
) {
  try {
    storage?.setItem(`${STORAGE_PREFIX}${pubkey}`, JSON.stringify(ledger));
  } catch (error) {
    console.warn("Couldn’t save the proposal alert state", error);
  }
}

function shorten(text: string, max: number) {
  const line = text.replace(/\s+/g, " ").trim();
  return line.length > max ? `${line.slice(0, max - 1).trimEnd()}…` : line;
}

function span(seconds: number) {
  const minutes = Math.max(1, Math.round(seconds / 60));
  if (minutes < 60) return `${minutes} min`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest ? `${hours} h ${rest} min` : `${hours} h`;
}

export function proposalAlertText(
  alert: ProposalAlert,
  requesterLabel: string,
  nowSeconds: number,
): { title: string; body: string } {
  const { proposal } = alert;
  const change = `${proposal.operation} ${proposal.target.kind} ${proposal.target.name} in ${proposal.workspace}`;
  const risk = proposal.highRisk.length > 0 ? "High risk · " : "";
  if (alert.kind === "soon") {
    return {
      title: `Approval expires in ${span(proposal.expiresAt - nowSeconds)}`,
      body: `${risk}${requesterLabel}: ${change}`,
    };
  }
  const reason = shorten(proposal.reason, 140);
  return {
    title: `${requesterLabel} asks for approval`,
    body: `${risk}${change}${reason ? ` · ${reason}` : ""}`,
  };
}
