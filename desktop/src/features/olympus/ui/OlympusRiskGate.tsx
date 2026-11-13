import * as React from "react";
import { ShieldAlert } from "lucide-react";

import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/shared/ui/alert-dialog";
import { Button } from "@/shared/ui/button";
import { olympusRiskLabel } from "../lib/olympusRisk";

type Pending = { risks: string[]; title: string; run: () => void };

export function useOlympusRiskGate() {
  const [pending, setPending] = React.useState<Pending | null>(null);
  const guard = React.useCallback(
    (title: string, risks: string[], run: (confirmed: boolean) => void) => {
      if (risks.length === 0) run(false);
      else setPending({ risks, title, run: () => run(true) });
    },
    [],
  );
  const dialog = (
    <AlertDialog
      onOpenChange={(open) => {
        if (!open) setPending(null);
      }}
      open={pending !== null}
    >
      <AlertDialogContent data-testid="olympus-risk-dialog">
        <AlertDialogHeader>
          <AlertDialogTitle className="flex items-center gap-2">
            <ShieldAlert aria-hidden className="h-5 w-5 text-destructive" />
            High-risk change
          </AlertDialogTitle>
          <AlertDialogDescription>
            {pending?.title}: this change touches high-risk settings.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <ul className="list-disc space-y-1 pl-5 text-sm text-foreground">
          {pending?.risks.map((risk) => (
            <li key={risk}>{olympusRiskLabel(risk)}</li>
          ))}
        </ul>
        <p className="text-sm text-muted-foreground">
          Confirm only if you expect this change. Hephaestus applies it at once.
        </p>
        <AlertDialogFooter>
          <AlertDialogCancel asChild>
            <Button type="button" variant="outline">
              Cancel
            </Button>
          </AlertDialogCancel>
          <AlertDialogAction asChild>
            <Button
              onClick={() => {
                pending?.run();
                setPending(null);
              }}
              type="button"
              variant="destructive"
            >
              Confirm high-risk change
            </Button>
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
  return { guard, dialog };
}
