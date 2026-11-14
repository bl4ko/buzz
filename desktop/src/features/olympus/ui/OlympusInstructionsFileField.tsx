import type { UseQueryResult } from "@tanstack/react-query";
import { FileText, RefreshCw, TriangleAlert } from "lucide-react";

import type { OlympusInstructionsFile } from "@/features/agents/lib/olympusAgents";
import { Button } from "@/shared/ui/button";
import { Skeleton } from "@/shared/ui/skeleton";
import { Textarea } from "@/shared/ui/textarea";
import {
  OLYMPUS_FILE_MAX_BYTES,
  type OlympusFileVersion,
} from "../lib/olympusInstructionsFile";

export function OlympusInstructionsFileField({
  file,
  id,
  onChange,
  query,
  tooBig,
  value,
}: {
  file: OlympusInstructionsFile;
  id: string;
  onChange: (value: string | null) => void;
  query: UseQueryResult<OlympusFileVersion>;
  tooBig: boolean;
  value: string;
}) {
  const version = query.data;
  return (
    <div className="space-y-1.5" data-testid="olympus-instructions-file">
      <div className="flex items-center justify-between gap-2">
        <label className="text-sm font-medium" htmlFor={id}>
          Instructions
        </label>
        <span className="flex min-w-0 items-center gap-1.5 text-xs text-muted-foreground">
          <FileText aria-hidden className="h-3.5 w-3.5 shrink-0" />
          <span className="truncate font-mono" title={file.url ?? undefined}>
            {file.repo}/{file.path}
          </span>
          {version ? (
            <span className="shrink-0 font-mono" title={version.base}>
              · {version.base.slice(0, 7)}
            </span>
          ) : null}
          <Button
            aria-label="Read the file again"
            className="h-6 w-6 shrink-0"
            disabled={query.isFetching}
            onClick={() => {
              onChange(null);
              void query.refetch();
            }}
            size="icon"
            type="button"
            variant="ghost"
          >
            <RefreshCw
              className={query.isFetching ? "animate-spin" : undefined}
            />
          </Button>
        </span>
      </div>
      {query.isLoading ? (
        <div className="space-y-2" data-testid="olympus-instructions-loading">
          <Skeleton className="h-48 w-full rounded-md" />
          <p className="text-xs text-muted-foreground">
            Reading the file from Olympus git…
          </p>
        </div>
      ) : query.error ? (
        <div
          className="flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive"
          role="alert"
        >
          <TriangleAlert aria-hidden className="mt-0.5 h-4 w-4 shrink-0" />
          <span className="min-w-0 flex-1">
            Couldn’t read the instructions from Olympus git.{" "}
            {query.error instanceof Error ? query.error.message : ""}
          </span>
          <Button
            onClick={() => void query.refetch()}
            size="sm"
            type="button"
            variant="outline"
          >
            Try again
          </Button>
        </div>
      ) : (
        <>
          <Textarea
            className="min-h-64 font-mono text-xs"
            id={id}
            onChange={(event) => onChange(event.target.value)}
            spellCheck={false}
            value={value}
          />
          <p
            className={
              tooBig
                ? "text-xs text-destructive"
                : "text-xs text-muted-foreground"
            }
          >
            {tooBig
              ? `The file is larger than ${OLYMPUS_FILE_MAX_BYTES / 1024} KiB.`
              : "Saving commits the file to Olympus git. You see the diff first."}
          </p>
        </>
      )}
    </div>
  );
}
