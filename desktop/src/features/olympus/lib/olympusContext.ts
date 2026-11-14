export type OlympusContextUse = {
  sessionId: string;
  channelId: string | null;
  at: number;
  used: number | null;
  size: number | null;
  turns: number;
  startedAt: number;
  compactions: number;
};

function count(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value >= 0
    ? value
    : null;
}

export function parseOlympusContext(
  payload: unknown,
): OlympusContextUse | null {
  if (!payload || typeof payload !== "object") return null;
  const p = payload as Record<string, unknown>;
  const context = p.context as Record<string, unknown> | null | undefined;
  if (!context || typeof context !== "object") return null;
  const at = Date.parse(String(p.timestamp ?? ""));
  if (typeof p.sessionId !== "string" || Number.isNaN(at)) return null;
  return {
    sessionId: p.sessionId,
    channelId: typeof p.channelId === "string" ? p.channelId : null,
    at: Math.floor(at / 1_000),
    used: count(context.used),
    size: count(context.size) || null,
    turns: count(context.turns) ?? 0,
    startedAt: count(context.startedAt) ?? 0,
    compactions: count(context.compactions) ?? 0,
  };
}

export function latestOlympusContexts(
  entries: readonly OlympusContextUse[],
  channelId?: string | null,
): OlympusContextUse[] {
  const bySession = new Map<string, OlympusContextUse>();
  for (const entry of entries) {
    if (channelId && entry.channelId !== channelId) continue;
    const current = bySession.get(entry.sessionId);
    if (
      !current ||
      entry.at > current.at ||
      (entry.at === current.at && entry.turns > current.turns)
    ) {
      bySession.set(entry.sessionId, entry);
    }
  }
  return [...bySession.values()].sort((a, b) => b.at - a.at);
}

export function olympusContextPercent(entry: OlympusContextUse): number | null {
  if (entry.used === null || !entry.size) return null;
  return Math.min(100, Math.round((entry.used / entry.size) * 100));
}
