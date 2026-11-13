import * as React from "react";

import type { OlympusProposal } from "@/features/agents/lib/olympusProposals";
import { sendDesktopNotification } from "@/features/notifications/lib/desktop";
import type { Channel } from "@/shared/api/types";
import { KIND_OLYMPUS_PROPOSAL } from "@/shared/constants/kinds";
import { normalizePubkey } from "@/shared/lib/pubkey";
import { findMasterDm } from "./lib/masterAgent";
import {
  loadProposalAlertLedger,
  planProposalAlerts,
  type ProposalAlertLedger,
  proposalAlertText,
  recordProposalAlert,
  saveProposalAlertLedger,
} from "./lib/proposalAlerts";

const MAX_TIMER_MS = 2_147_483_647;

function storage(): Storage | null {
  return typeof window === "undefined" ? null : window.localStorage;
}

export function useProposalAlerts({
  channels,
  currentPubkey,
  enabled,
  masterLabel,
  masterPubkey,
  proposals,
}: {
  channels: readonly Channel[];
  currentPubkey: string | undefined;
  enabled: boolean;
  masterLabel: string | null;
  masterPubkey: string | null;
  proposals: readonly OlympusProposal[];
}) {
  const me = currentPubkey ? normalizePubkey(currentPubkey) : "";
  const [tick, setTick] = React.useState(0);
  const ledger = React.useRef<{
    me: string;
    value: ProposalAlertLedger;
  } | null>(null);
  const inFlight = React.useRef(new Set<string>());

  React.useEffect(() => {
    void tick;
    if (!enabled || !me) return;
    if (ledger.current?.me !== me) {
      ledger.current = { me, value: loadProposalAlertLedger(storage(), me) };
    }
    const now = Math.floor(Date.now() / 1_000);
    const plan = planProposalAlerts(proposals, now, ledger.current.value);
    for (const alert of plan.alerts) {
      const id = `${me}:${alert.kind}:${alert.proposal.author}:${alert.proposal.name}`;
      if (inFlight.current.has(id)) continue;
      inFlight.current.add(id);
      const requesterKey = alert.proposal.requesterKey;
      const label =
        requesterKey && requesterKey === masterPubkey && masterLabel
          ? masterLabel
          : alert.proposal.requester;
      const dm = requesterKey ? findMasterDm(channels, me, requesterKey) : null;
      void sendDesktopNotification({
        ...proposalAlertText(alert, label, now),
        target: dm
          ? {
              channelId: dm.id,
              channelName: label,
              eventId: null,
              kind: KIND_OLYMPUS_PROPOSAL,
            }
          : undefined,
      })
        .then((sent) => {
          if (!sent || ledger.current?.me !== me) return;
          ledger.current.value = recordProposalAlert(
            ledger.current.value,
            alert,
            Math.floor(Date.now() / 1_000),
          );
          saveProposalAlertLedger(storage(), me, ledger.current.value);
        })
        .catch((error) => {
          console.warn("Couldn’t send the proposal notification", error);
        })
        .finally(() => {
          inFlight.current.delete(id);
        });
    }
    if (plan.nextCheckAt === null) return;
    const timer = setTimeout(
      () => setTick((value) => value + 1),
      Math.min(MAX_TIMER_MS, Math.max(0, plan.nextCheckAt - now) * 1_000 + 500),
    );
    return () => clearTimeout(timer);
  }, [channels, enabled, masterLabel, masterPubkey, me, proposals, tick]);
}
