import * as React from "react";

import { Button } from "@/shared/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/shared/ui/dialog";
import { Input } from "@/shared/ui/input";
import {
  CUSTOM_TAB_TYPES,
  type ChannelTab,
  type CustomTabType,
  newTabId,
  validateTabValue,
} from "../lib/channelTabs";

const TYPE_LABEL: Record<CustomTabType, string> = {
  link: "Link",
  search: "Search",
  thread: "Thread",
  canvas: "Canvas",
};
const VALUE_LABEL: Record<Exclude<CustomTabType, "canvas">, string> = {
  link: "https URL",
  search: "Search, for example from:Athene CVE",
  thread: "Thread root event ID",
};

function TabForm({
  initial,
  onSubmit,
}: {
  initial: ChannelTab | null;
  onSubmit: (tab: ChannelTab) => Promise<void>;
}) {
  const [type, setType] = React.useState<CustomTabType>(
    (initial?.type as CustomTabType) ?? "link",
  );
  const [title, setTitle] = React.useState(initial?.title ?? "");
  const [value, setValue] = React.useState(initial?.value ?? "");
  const [error, setError] = React.useState<string | null>(null);
  const editing = initial !== null;
  const attempt = async (tab: ChannelTab) => {
    try {
      await onSubmit(tab);
    } catch {
      setError("Couldn't save the tab. Try again.");
    }
  };
  const submit = async () => {
    const cleanTitle = title.trim();
    if (cleanTitle === "" || [...cleanTitle].length > 40) {
      setError("Enter a title of 1 to 40 characters.");
      return;
    }
    if (initial) {
      await attempt({ ...initial, title: cleanTitle });
      return;
    }
    const cleanValue = type === "canvas" ? newTabId() : value.trim();
    const problem = validateTabValue(type, cleanValue);
    if (problem) {
      setError(problem);
      return;
    }
    await attempt({
      id: newTabId(),
      type,
      title: cleanTitle,
      value: cleanValue,
    });
  };
  return (
    <>
      <DialogHeader>
        <DialogTitle>{editing ? "Rename tab" : "Add tab"}</DialogTitle>
      </DialogHeader>
      {editing ? null : (
        <fieldset className="m-0 flex gap-1 border-0 p-0">
          {CUSTOM_TAB_TYPES.map((option) => (
            <Button
              data-testid={`tab-type-${option}`}
              key={option}
              onClick={() => setType(option)}
              size="sm"
              type="button"
              variant={type === option ? "secondary" : "ghost"}
            >
              {TYPE_LABEL[option]}
            </Button>
          ))}
        </fieldset>
      )}
      <Input
        aria-label="Title"
        data-testid="tab-title"
        onChange={(event) => setTitle(event.target.value)}
        placeholder="Title"
        value={title}
      />
      {!editing && type !== "canvas" ? (
        <Input
          aria-label={VALUE_LABEL[type]}
          data-testid="tab-value"
          onChange={(event) => setValue(event.target.value)}
          placeholder={VALUE_LABEL[type]}
          value={value}
        />
      ) : null}
      {error ? (
        <p className="text-sm text-destructive" data-testid="tab-error">
          {error}
        </p>
      ) : null}
      <DialogFooter>
        <Button
          data-testid="tab-submit"
          onClick={() => void submit()}
          type="button"
        >
          {editing ? "Save" : "Add"}
        </Button>
      </DialogFooter>
    </>
  );
}

export function AddChannelTabDialog({
  open,
  initial,
  onOpenChange,
  onSubmit,
}: {
  open: boolean;
  initial: ChannelTab | null;
  onOpenChange: (open: boolean) => void;
  onSubmit: (tab: ChannelTab) => Promise<void>;
}) {
  return (
    <Dialog onOpenChange={onOpenChange} open={open}>
      <DialogContent>
        <TabForm initial={initial} onSubmit={onSubmit} />
      </DialogContent>
    </Dialog>
  );
}
