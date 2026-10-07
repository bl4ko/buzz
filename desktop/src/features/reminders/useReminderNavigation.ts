import * as React from "react";

import { useAppNavigation } from "@/app/navigation/useAppNavigation";
import { useCommunities } from "@/features/communities/useCommunities";
import { matchesDetachedToastScope } from "@/features/messages/lib/detachedToastScope";
import { resolveReminderDestination } from "./lib/reminderNavigation";
import type { ReminderTarget } from "./lib/reminderTypes";

export function useReminderNavigation(pubkey: string | undefined) {
  const { goChannel } = useAppNavigation();
  const { activeCommunity, reinitKey } = useCommunities();
  const relayUrl = activeCommunity?.relayUrl ?? "";
  const scopeKey = `${activeCommunity?.id ?? ""}\u0000${relayUrl}\u0000${pubkey ?? ""}\u0000${reinitKey}`;
  const scopeRef = React.useRef<{ key: string } | null>(null);
  React.useLayoutEffect(() => {
    scopeRef.current = { key: scopeKey };
    return () => {
      scopeRef.current = null;
    };
  }, [scopeKey]);

  return React.useCallback(
    async (target: ReminderTarget | undefined) => {
      const scope = scopeRef.current;
      if (!scope || !pubkey || !matchesDetachedToastScope(relayUrl, pubkey))
        return;
      const destination = await resolveReminderDestination(target);
      if (
        !destination ||
        scope !== scopeRef.current ||
        !matchesDetachedToastScope(relayUrl, pubkey)
      )
        return;
      void goChannel(destination.channelId, {
        messageId: destination.messageId,
        threadRootId: destination.threadRootId,
      });
    },
    [goChannel, pubkey, relayUrl],
  );
}
