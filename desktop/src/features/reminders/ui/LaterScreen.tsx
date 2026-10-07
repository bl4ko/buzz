import * as React from "react";
import { Bookmark } from "lucide-react";
import { toast } from "sonner";

import {
  useReminderMutations,
  useRemindersQuery,
} from "@/features/reminders/hooks";
import { useReminderNavigation } from "@/features/reminders/useReminderNavigation";
import { useReminderSources } from "@/features/reminders/ui/RemindersPanel";
import { SnoozeMenu } from "@/features/reminders/ui/SnoozeMenu";
import { useIdentityQuery } from "@/shared/api/hooks";
import { TopChromeInsetHeader } from "@/shared/layout/TopChromeInsetHeader";
import { Button } from "@/shared/ui/button";
import { Tabs, TabsList, TabsTrigger } from "@/shared/ui/tabs";
import type { ReminderStatus } from "@/features/reminders/lib/reminderTypes";

export function LaterScreen() {
  const pubkey = useIdentityQuery().data?.pubkey;
  const query = useRemindersQuery(pubkey);
  const { complete, snooze, cancel } = useReminderMutations(pubkey ?? "");
  const openMessage = useReminderNavigation(pubkey);
  const [status, setStatus] = React.useState<ReminderStatus>("pending");
  const sources = useReminderSources(query.data ?? []);
  const items = (query.data ?? [])
    .filter((item) => item.content.status === status)
    .sort((a, b) => b.createdAt - a.createdAt);
  const busy = complete.isPending || snooze.isPending || cancel.isPending;
  const result = { onError: () => toast.error("Failed to update saved item") };

  return (
    <section className="flex h-full min-h-0 flex-col" data-testid="later-view">
      <TopChromeInsetHeader flush>
        <h1 className="flex items-center gap-2 px-4 py-3 text-base font-semibold">
          <Bookmark className="h-4 w-4" />
          Later
        </h1>
      </TopChromeInsetHeader>
      <Tabs
        value={status}
        onValueChange={(value) => setStatus(value as ReminderStatus)}
        className="px-4 py-2"
      >
        <TabsList aria-label="Saved item status">
          <TabsTrigger value="pending">In progress</TabsTrigger>
          <TabsTrigger value="done">Completed</TabsTrigger>
          <TabsTrigger value="cancelled">Archived</TabsTrigger>
        </TabsList>
      </Tabs>
      <div className="min-h-0 flex-1 overflow-y-auto p-4">
        {query.isPending ? <p>Loading saved items...</p> : null}
        {query.isError ? (
          <div role="alert">
            Could not load saved items.{" "}
            <Button onClick={() => void query.refetch()}>Retry</Button>
          </div>
        ) : null}
        {query.isSuccess && items.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            No items here. Select Save for later from a message menu.
          </p>
        ) : null}
        <div className="mx-auto max-w-3xl space-y-3">
          {items.map((item) => {
            const source = sources.get(item.id);
            return (
              <article
                key={item.id}
                className="rounded-lg border p-4"
                data-testid={`later-item-${item.id}`}
              >
                {source ? (
                  <p className="mb-2 text-xs text-muted-foreground">
                    {source.authorLabel} · {source.channelLabel}
                  </p>
                ) : null}
                <p className="whitespace-pre-wrap break-words text-sm">
                  {item.content.target?.preview ||
                    item.content.note ||
                    "Saved item"}
                </p>
                {item.content.target && item.content.note ? (
                  <p className="mt-2 text-sm text-muted-foreground">
                    {item.content.note}
                  </p>
                ) : null}
                {item.notBefore !== undefined ? (
                  <p className="mt-2 text-xs text-muted-foreground">
                    Reminder:{" "}
                    {new Date(item.notBefore * 1_000).toLocaleString()}
                  </p>
                ) : null}
                <div className="mt-3 flex flex-wrap items-center gap-2">
                  {item.content.target ? (
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => void openMessage(item.content.target)}
                    >
                      Open message
                    </Button>
                  ) : null}
                  {status === "pending" ? (
                    <>
                      <Button
                        size="sm"
                        disabled={busy}
                        onClick={() => complete.mutate(item, result)}
                      >
                        Mark complete
                      </Button>
                      <SnoozeMenu
                        disabled={busy}
                        onSnooze={(notBefore) =>
                          snooze.mutate({ reminder: item, notBefore }, result)
                        }
                      />
                    </>
                  ) : (
                    <Button
                      size="sm"
                      disabled={busy}
                      onClick={() => snooze.mutate({ reminder: item }, result)}
                    >
                      Move to In progress
                    </Button>
                  )}
                  {status !== "cancelled" ? (
                    <Button
                      size="sm"
                      variant="ghost"
                      disabled={busy}
                      onClick={() => cancel.mutate(item, result)}
                    >
                      Archive
                    </Button>
                  ) : null}
                </div>
              </article>
            );
          })}
        </div>
      </div>
    </section>
  );
}
