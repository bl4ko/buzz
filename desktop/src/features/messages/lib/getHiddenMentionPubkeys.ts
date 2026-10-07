import { orderMentionPubkeysByText } from "@/features/messages/lib/orderMentionPubkeys";
import { normalizePubkey } from "@/shared/lib/pubkey";

/** Notified `p` recipients the reader cannot see in the body or address prefix. */
export function getHiddenMentionPubkeys(
  body: string,
  tags: readonly string[][] | undefined,
  shownPubkeys: readonly (string | null | undefined)[],
  mentionPubkeysByName: Readonly<Record<string, string>> | undefined,
  mentionNames?: readonly string[],
): string[] {
  const shown = new Set(
    orderMentionPubkeysByText(
      body,
      mentionPubkeysByName,
      () => true,
      mentionNames,
    ),
  );
  for (const pubkey of shownPubkeys) {
    if (pubkey) shown.add(normalizePubkey(pubkey));
  }
  const notified = (tags ?? [])
    .filter((tag) => tag[0] === "p" && Boolean(tag[1]))
    .map((tag) => normalizePubkey(tag[1]));
  return [...new Set(notified)].filter((pubkey) => !shown.has(pubkey));
}
