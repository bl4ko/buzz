import * as React from "react";
import { toast } from "sonner";

import {
  useReminderMutations,
  useRemindersQuery,
} from "@/features/reminders/hooks";
import type { ReminderTarget } from "@/features/reminders/lib/reminderTypes";
import { RemindMeLaterDialog } from "./RemindMeLaterDialog";

type RemindMeLaterContextValue = {
  openReminder: (target: ReminderTarget) => void;
  saveForLater: (target: ReminderTarget) => void;
  /** Event IDs of messages with a pending reminder, for channel tinting. */
  activeReminderEventIds: ReadonlySet<string>;
};

const RemindMeLaterContext = React.createContext<RemindMeLaterContextValue>({
  openReminder: () => {},
  saveForLater: () => {},
  activeReminderEventIds: new Set(),
});

export function useRemindLater() {
  return React.useContext(RemindMeLaterContext);
}

export function RemindMeLaterProvider({
  pubkey,
  children,
}: {
  pubkey?: string;
  children: React.ReactNode;
}) {
  const [open, setOpen] = React.useState(false);
  const [target, setTarget] = React.useState<ReminderTarget | null>(null);

  const openReminder = React.useCallback((t: ReminderTarget) => {
    setTarget(t);
    setOpen(true);
  }, []);

  const remindersQuery = useRemindersQuery(pubkey);
  const reminders = remindersQuery.data;
  const { create } = useReminderMutations(pubkey ?? "");
  const saveForLater = React.useCallback(
    (t: ReminderTarget) => {
      if (!pubkey || create.isPending) return;
      if (!t.channelId || !t.eventId || !t.authorPubkey) return;
      if (!reminders) {
        toast.error("Saved items are still loading. Try again.");
        return;
      }
      const matches = reminders.filter(
        (r) => r.content.target?.eventId === t.eventId,
      );
      if (matches.some((item) => item.content.status === "pending")) {
        toast.success("Already saved in Later");
        return;
      }
      const previous = matches.sort((a, b) => b.createdAt - a.createdAt)[0];
      create.mutate(
        { target: t, previous },
        {
          onSuccess: () => toast.success("Saved for later"),
          onError: () => toast.error("Failed to save for later"),
        },
      );
    },
    [pubkey, create, reminders],
  );
  const activeReminderEventIds = React.useMemo(() => {
    const ids = new Set<string>();
    for (const reminder of reminders ?? []) {
      if (
        reminder.content.status === "pending" &&
        reminder.content.target?.eventId
      ) {
        ids.add(reminder.content.target.eventId);
      }
    }
    return ids;
  }, [reminders]);

  const contextValue = React.useMemo(
    () => ({ openReminder, saveForLater, activeReminderEventIds }),
    [openReminder, saveForLater, activeReminderEventIds],
  );

  return (
    <RemindMeLaterContext.Provider value={contextValue}>
      {children}
      <RemindMeLaterDialog open={open} onOpenChange={setOpen} target={target} />
    </RemindMeLaterContext.Provider>
  );
}
