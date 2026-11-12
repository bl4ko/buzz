import { useEffect, useRef } from "react";

import { fetchCommunityName } from "@/shared/api/communityProfile";

import { deriveCommunityName } from "./communityStorage";
import type { Community } from "./types";

const UPSTREAM_RELAY_NAME = "Buzz Relay";
const MAX_RELAY_NAME_LENGTH = 64;

export function hasDerivedCommunityName(community: Community): boolean {
  return community.name === deriveCommunityName(community.relayUrl);
}

/** The relay's own name when it can replace a host-derived community name. */
export function relayCommunityName(
  name: string | null | undefined,
): string | null {
  const trimmed = name?.trim() ?? "";
  if (
    trimmed.length === 0 ||
    trimmed.length > MAX_RELAY_NAME_LENGTH ||
    trimmed === UPSTREAM_RELAY_NAME
  ) {
    return null;
  }
  return trimmed;
}

/**
 * Names a community after its relay (NIP-11 `name`) while the local name is
 * still the one derived from the relay host. A name the user chose stays.
 */
export function useRelayCommunityNames(
  communities: Community[],
  rename: (id: string, name: string) => void,
) {
  const communitiesRef = useRef(communities);
  communitiesRef.current = communities;
  const renameRef = useRef(rename);
  renameRef.current = rename;

  const pending = communities
    .filter(hasDerivedCommunityName)
    .map((community) => `${community.id} ${community.relayUrl}`)
    .join("\n");

  useEffect(() => {
    if (pending.length === 0) return;
    let disposed = false;
    for (const line of pending.split("\n")) {
      const [id, relayUrl] = line.split(" ");
      fetchCommunityName(relayUrl)
        .then((relayName) => {
          const name = relayCommunityName(relayName);
          const current = communitiesRef.current.find((c) => c.id === id);
          if (
            disposed ||
            name === null ||
            !current ||
            current.relayUrl !== relayUrl ||
            !hasDerivedCommunityName(current)
          ) {
            return;
          }
          renameRef.current(id, name);
        })
        .catch(() => {});
    }
    return () => {
      disposed = true;
    };
  }, [pending]);
}
