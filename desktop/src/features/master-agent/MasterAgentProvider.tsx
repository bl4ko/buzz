import * as React from "react";
import { toast } from "sonner";

import { useOlympusAgents } from "@/features/agents/useOlympusAgents";
import {
  loadDraftEntry,
  saveDraftEntry,
} from "@/features/messages/lib/useDrafts";
import { usePresenceQuery } from "@/features/presence/hooks";
import { useUsersBatchQuery } from "@/features/profile/hooks";
import type { Channel, PresenceStatus } from "@/shared/api/types";
import { hasPrimaryShortcutModifier } from "@/shared/lib/platform";
import { composerSeed, focusComposer, selectionSeed } from "./lib/askSeed";
import {
  type AskMasterSeed,
  buildAskDraft,
  findMasterAgent,
  findMasterDm,
  masterAgentLabel,
  masterAgentPicture,
  mergeAskDraft,
} from "./lib/masterAgent";

export type MasterAgent = {
  pubkey: string;
  label: string;
  avatarUrl: string | null;
  presence: PresenceStatus;
  dmChannel: Channel | null;
};

type MasterAgentContextValue = {
  agent: MasterAgent;
  ask: (seed?: AskMasterSeed | null) => Promise<void>;
};

const MasterAgentContext = React.createContext<MasterAgentContextValue | null>(
  null,
);

export function useMasterAgent() {
  return React.useContext(MasterAgentContext);
}

function seedDraft(channelId: string, seed: AskMasterSeed) {
  const next = buildAskDraft(seed);
  if (!next) return;
  const existing = loadDraftEntry(channelId);
  const content = mergeAskDraft(existing?.content, next);
  const now = new Date().toISOString();
  saveDraftEntry(channelId, {
    channelId,
    content,
    createdAt: existing?.createdAt ?? now,
    mentionRefs: existing?.mentionRefs ?? [],
    pendingImeta: existing?.pendingImeta ?? [],
    selectionEnd: content.length,
    selectionStart: content.length,
    spoileredAttachmentUrls: existing?.spoileredAttachmentUrls ?? [],
    status: "active",
    updatedAt: now,
  });
}

export function MasterAgentProvider({
  channels,
  children,
  currentChannelId,
  currentPubkey,
  goChannel,
  openDm,
  shortcutDisabled,
}: {
  channels: readonly Channel[];
  children: React.ReactNode;
  currentChannelId: string | null;
  currentPubkey: string | undefined;
  goChannel: (channelId: string) => unknown;
  openDm: (input: { pubkeys: string[] }) => Promise<Channel>;
  shortcutDisabled: boolean;
}) {
  const { groups } = useOlympusAgents();
  const record = React.useMemo(() => findMasterAgent(groups), [groups]);
  const pubkey = record?.publicKey ?? null;
  const keys = React.useMemo(() => (pubkey ? [pubkey] : []), [pubkey]);
  const profileQuery = useUsersBatchQuery(keys);
  const presenceQuery = usePresenceQuery(keys);
  const profile = pubkey ? profileQuery.data?.profiles[pubkey] : undefined;
  const presence = pubkey ? presenceQuery.data?.[pubkey] : undefined;
  const dmChannel = React.useMemo(
    () =>
      pubkey && currentPubkey
        ? findMasterDm(channels, currentPubkey, pubkey)
        : null,
    [channels, currentPubkey, pubkey],
  );

  const agent = React.useMemo<MasterAgent | null>(
    () =>
      record && pubkey
        ? {
            pubkey,
            label: masterAgentLabel(record, profile),
            avatarUrl: masterAgentPicture(record, profile),
            presence: presence ?? "offline",
            dmChannel,
          }
        : null,
    [dmChannel, presence, profile, pubkey, record],
  );

  const ask = React.useCallback(
    async (seed?: AskMasterSeed | null) => {
      if (!pubkey) return;
      if (dmChannel && dmChannel.id === currentChannelId) {
        focusComposer(document);
        return;
      }
      try {
        const channel = dmChannel ?? (await openDm({ pubkeys: [pubkey] }));
        if (seed) seedDraft(channel.id, seed);
        await goChannel(channel.id);
      } catch (error) {
        console.error("Couldn’t open the master agent", error);
        toast.error("Couldn’t open the direct message");
      }
    },
    [currentChannelId, dmChannel, goChannel, openDm, pubkey],
  );

  React.useEffect(() => {
    if (!pubkey || shortcutDisabled) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (
        event.code !== "KeyJ" ||
        !hasPrimaryShortcutModifier(event) ||
        event.altKey ||
        event.shiftKey ||
        event.repeat ||
        event.isComposing
      ) {
        return;
      }
      event.preventDefault();
      event.stopPropagation();
      const seed =
        selectionSeed(window.getSelection(), currentChannelId) ??
        composerSeed(document);
      void ask(seed);
    };
    window.addEventListener("keydown", onKeyDown, true);
    return () => window.removeEventListener("keydown", onKeyDown, true);
  }, [ask, currentChannelId, pubkey, shortcutDisabled]);

  const value = React.useMemo(
    () => (agent ? { agent, ask } : null),
    [agent, ask],
  );

  return (
    <MasterAgentContext.Provider value={value}>
      {children}
    </MasterAgentContext.Provider>
  );
}
