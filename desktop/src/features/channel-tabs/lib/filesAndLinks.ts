import { getThreadReference } from "@/features/messages/lib/threading";
import type { RelayEvent } from "@/shared/api/types";
import { parseImetaTags } from "@/shared/ui/markdown/parseImeta";

export type FileLinkKind = "file" | "media" | "link";
export type FileLinkFilter = "all" | "files" | "media" | "links";
export type FileLinkItem = {
  key: string;
  kind: FileLinkKind;
  url: string;
  name: string;
  host: string;
  path: string;
  mime: string | null;
  thumb: string | null;
  messageId: string;
  rootId: string | null;
  pubkey: string;
  createdAt: number;
};

const URL_RE = /https?:\/\/[^\s<>"'`]+/g;
const FILTER_KIND: Record<Exclude<FileLinkFilter, "all">, FileLinkKind> = {
  files: "file",
  media: "media",
  links: "link",
};

function trimUrl(raw: string) {
  return raw.replace(/[).,;:!?\]]+$/, "");
}

function urlParts(url: string) {
  try {
    const parsed = new URL(url);
    return { host: parsed.host, path: parsed.pathname };
  } catch {
    return null;
  }
}

export function extractFilesAndLinks(
  events: readonly RelayEvent[],
): FileLinkItem[] {
  const items = new Map<string, FileLinkItem>();
  for (const event of events) {
    const rootId = getThreadReference(event.tags).rootId ?? null;
    const base = {
      messageId: event.id,
      rootId,
      pubkey: event.pubkey,
      createdAt: event.created_at,
    };
    const imeta = parseImetaTags(event.tags);
    for (const [url, entry] of imeta) {
      const parts = urlParts(url);
      if (!parts) continue;
      const mime = entry.m ?? null;
      const kind: FileLinkKind =
        mime && /^(image|video)\//.test(mime) ? "media" : "file";
      const name =
        entry.filename ??
        decodeURIComponent(parts.path.split("/").pop() || parts.host);
      items.set(`${event.id}:${url}`, {
        key: `${event.id}:${url}`,
        kind,
        url,
        name,
        ...parts,
        mime,
        thumb: entry.thumb ?? entry.image ?? null,
        ...base,
      });
    }
    for (const raw of event.content.match(URL_RE) ?? []) {
      const url = trimUrl(raw);
      const parts = urlParts(url);
      if (!parts || imeta.has(url) || items.has(`${event.id}:${url}`)) continue;
      items.set(`${event.id}:${url}`, {
        key: `${event.id}:${url}`,
        kind: "link",
        url,
        name: parts.host + parts.path,
        ...parts,
        mime: null,
        thumb: null,
        ...base,
      });
    }
  }
  return [...items.values()].sort(
    (a, b) => b.createdAt - a.createdAt || (a.key < b.key ? -1 : 1),
  );
}

export function filterFilesAndLinks(
  items: readonly FileLinkItem[],
  filter: FileLinkFilter,
  query: string,
): FileLinkItem[] {
  const needle = query.trim().toLowerCase();
  return items.filter(
    (item) =>
      (filter === "all" || item.kind === FILTER_KIND[filter]) &&
      (needle === "" ||
        `${item.name} ${item.url}`.toLowerCase().includes(needle)),
  );
}
