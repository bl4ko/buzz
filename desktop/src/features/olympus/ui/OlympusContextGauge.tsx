import { formatCompactCount } from "@/features/agents/lib/olympusUsage";
import { cn } from "@/shared/lib/cn";
import { useNow } from "@/shared/lib/useNow";
import { Progress } from "@/shared/ui/progress";
import {
  latestOlympusContexts,
  type OlympusContextUse,
  olympusContextPercent,
} from "../lib/olympusContext";
import { useOlympusContext } from "../useOlympusContext";

function ago(atSeconds: number, nowMs: number) {
  const seconds = Math.max(0, Math.floor(nowMs / 1_000) - atSeconds);
  if (seconds < 3_600) return `${Math.floor(seconds / 60)}m`;
  if (seconds < 86_400) return `${Math.floor(seconds / 3_600)}h`;
  return `${Math.floor(seconds / 86_400)}d`;
}

function plural(count: number, word: string) {
  return `${count} ${word}${count === 1 ? "" : "s"}`;
}

function ContextRow({ entry, now }: { entry: OlympusContextUse; now: number }) {
  const percent = olympusContextPercent(entry);
  const tokens =
    entry.used === null
      ? "not reported"
      : entry.size
        ? `${formatCompactCount(entry.used)} / ${formatCompactCount(entry.size)}`
        : formatCompactCount(entry.used);
  return (
    <div className="space-y-1" data-testid="olympus-context-row">
      <div className="flex items-baseline justify-between gap-2 text-xs">
        <span className="font-medium tabular-nums">
          {percent === null ? "–" : `${percent}%`}
        </span>
        <span className="text-muted-foreground tabular-nums">{tokens}</span>
      </div>
      <Progress
        aria-label="Context window use"
        className={cn(
          "h-1.5",
          percent !== null && percent >= 80 && "[&>div]:bg-amber-500",
        )}
        value={percent ?? 0}
      />
      <p className="text-[11px] text-muted-foreground tabular-nums">
        {plural(entry.turns, "turn")} ·{" "}
        {plural(entry.compactions, "compaction")} · session{" "}
        {ago(entry.startedAt, now)} · updated {ago(entry.at, now)} ago
      </p>
    </div>
  );
}

export function OlympusContextGauge({
  agentPubkey,
  channelId,
  className,
  limit = 3,
}: {
  agentPubkey: string | null | undefined;
  channelId?: string | null;
  className?: string;
  limit?: number;
}) {
  const query = useOlympusContext(agentPubkey);
  const now = useNow(60_000);
  const entries = latestOlympusContexts(query.data ?? [], channelId).slice(
    0,
    channelId ? 1 : limit,
  );
  if (entries.length === 0) return null;
  return (
    <section
      className={cn("space-y-2", className)}
      data-testid="olympus-context-gauge"
    >
      <h3 className="text-xs font-medium text-muted-foreground">
        Context window
      </h3>
      {entries.map((entry) => (
        <ContextRow entry={entry} key={entry.sessionId} now={now} />
      ))}
    </section>
  );
}
