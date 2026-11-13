import * as React from "react";
import { toast } from "sonner";

import { useOlympusAgents } from "@/features/agents/useOlympusAgents";
import {
  loadDraftEntry,
  saveDraftEntry,
} from "@/features/messages/lib/useDrafts";
import { usePresenceQuery } from "@/features/presence/hooks";
import type { NotificationSettings } from "@/features/notifications/hooks";
import { useUsersBatchQuery } from "@/features/profile/hooks";
import type { Channel, PresenceStatus } from "@/shared/api/types";
import { hasPrimaryShortcutModifier } from "@/shared/lib/platform";
import { composerSeed, focusComposer, selectionSeed } from "./lib/askSeed";
import { useProposalAlerts } from "./useProposalAlerts";
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

let current: MasterAgentContextValue | null = null;
const listeners = new Set<() => void>();

function publish(next: MasterAgentContextValue | null) {
  if (next === current) return;
  current = next;
  for (const listener of listeners) listener();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

export function useMasterAgent() {
  return React.useSyncExternalStore(
    subscribe,
    () => current,
    () => null,
  );
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

export function useMasterAgentController({
  channels,
  currentChannelId,
  currentPubkey,
  goChannel,
  notificationSettings,
  openDm,
  shortcutDisabled,
}: {
  channels: readonly Channel[];
  currentChannelId: string | null;
  currentPubkey: string | undefined;
  goChannel: (channelId: string) => unknown;
  notificationSettings: NotificationSettings | null;
  openDm: (input: { pubkeys: string[] }) => Promise<Channel>;
  shortcutDisabled: boolean;
}) {
  const { groups, proposals } = useOlympusAgents();
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

  useProposalAlerts({
    channels,
    currentPubkey,
    masterLabel: agent?.label ?? null,
    masterPubkey: pubkey,
    notificationSettings,
    proposals,
  });

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

  React.useEffect(() => {
    publish(value);
  }, [value]);
  React.useEffect(() => () => publish(null), []);
}
