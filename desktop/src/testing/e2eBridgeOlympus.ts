import type { RelayEvent } from "@/shared/api/types";

export const MOCK_OLYMPUS_KINDS = new Set([30190, 30191, 30192, 44310, 44311]);

type OlympusFilter = {
  kinds?: readonly number[];
  authors?: readonly string[];
  "#p"?: readonly string[];
  "#e"?: readonly string[];
  "#d"?: readonly string[];
};

const store: RelayEvent[] = [];

export function resetMockOlympusEvents(seed: readonly RelayEvent[] = []) {
  store.length = 0;
  for (const event of seed) {
    store.push({ ...event, tags: event.tags.map((tag) => [...tag]) });
  }
}

export function isMockOlympusFilter(filter: OlympusFilter) {
  return filter.kinds?.some((kind) => MOCK_OLYMPUS_KINDS.has(kind)) ?? false;
}

function tagMatches(
  event: RelayEvent,
  name: string,
  values: readonly string[] | undefined,
) {
  return (
    !values ||
    event.tags.some((tag) => tag[0] === name && values.includes(tag[1] ?? ""))
  );
}

export function selectMockOlympusEvents(filter: OlympusFilter) {
  return store.filter(
    (event) =>
      (!filter.kinds || filter.kinds.includes(event.kind)) &&
      (!filter.authors || filter.authors.includes(event.pubkey)) &&
      tagMatches(event, "p", filter["#p"]) &&
      tagMatches(event, "e", filter["#e"]) &&
      tagMatches(event, "d", filter["#d"]),
  );
}

export function storeMockOlympusEvent(event: RelayEvent) {
  store.push(event);
}
