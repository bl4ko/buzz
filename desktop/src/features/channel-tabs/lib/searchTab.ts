import type { RelaySubscriptionFilter } from "@/shared/api/relayClientShared";
import { parseSearchOperators } from "@/features/search/lib/parseSearchOperators";

export function resolveSearchTab(
  value: string,
  members: readonly { pubkey: string; displayName?: string | null }[],
) {
  const parsed = parseSearchOperators(value);
  const base = { text: parsed.text, since: parsed.since, until: parsed.until };
  if (!parsed.from) return { ...base, authors: undefined, unresolved: null };
  const wanted = parsed.from.replace(/^@/, "").toLowerCase();
  const match = members.find(
    (member) =>
      member.pubkey.toLowerCase() === wanted ||
      (member.displayName ?? "").toLowerCase() === wanted,
  );
  return match
    ? { ...base, authors: [match.pubkey], unresolved: null }
    : { ...base, authors: undefined, unresolved: parsed.from };
}

export function authorOnlyFilter(
  search: {
    text: string;
    authors: string[] | undefined;
    since: number | null;
    until: number | null;
  },
  channelId: string,
): RelaySubscriptionFilter | null {
  if (search.text.trim() !== "" || !search.authors) return null;
  return {
    kinds: [9, 40002],
    "#h": [channelId],
    authors: search.authors,
    limit: 50,
    ...(search.since === null ? {} : { since: search.since }),
    ...(search.until === null ? {} : { until: search.until }),
  };
}
