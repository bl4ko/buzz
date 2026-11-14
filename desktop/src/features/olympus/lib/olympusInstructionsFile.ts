import { useQuery } from "@tanstack/react-query";

import type { OlympusInstructionsFile } from "@/features/agents/lib/olympusAgents";
import { invokeTauri } from "@/shared/api/tauri";

export const OLYMPUS_FILE_MAX_BYTES = 100 * 1024;

export type OlympusFileVersion = { base: string; content: string };

export async function readOlympusInstructionsFile(
  file: OlympusInstructionsFile,
): Promise<OlympusFileVersion> {
  if (!file.url) throw new Error("Hephaestus did not publish the clone URL.");
  return invokeTauri<OlympusFileVersion>("read_olympus_git_file", {
    cloneUrl: file.url,
    branch: file.branch,
    path: file.path,
  });
}

export function olympusInstructionsFileQueryKey(
  file: OlympusInstructionsFile | null,
) {
  return [
    "olympus-instructions-file",
    file?.url ?? null,
    file?.branch ?? null,
    file?.path ?? null,
  ] as const;
}

export function useOlympusInstructionsFile(
  file: OlympusInstructionsFile | null,
) {
  return useQuery({
    queryKey: olympusInstructionsFileQueryKey(file),
    queryFn: () => readOlympusInstructionsFile(file as OlympusInstructionsFile),
    enabled: file !== null,
    retry: false,
    staleTime: 0,
    gcTime: 60_000,
    refetchOnWindowFocus: false,
  });
}

export function olympusFileTooLarge(content: string) {
  return new TextEncoder().encode(content).length > OLYMPUS_FILE_MAX_BYTES;
}
