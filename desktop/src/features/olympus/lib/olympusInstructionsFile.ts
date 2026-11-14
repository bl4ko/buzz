import { useQuery } from "@tanstack/react-query";

import type { OlympusInstructionsFile } from "@/features/agents/lib/olympusAgents";
import {
  getProjectRepoFileContent,
  getProjectRepoSnapshot,
} from "@/shared/api/projectGit";

export const OLYMPUS_FILE_MAX_BYTES = 100 * 1024;

export type OlympusFileVersion = { base: string; content: string };

export async function readOlympusInstructionsFile(
  file: OlympusInstructionsFile,
): Promise<OlympusFileVersion> {
  if (!file.url) throw new Error("Hephaestus did not publish the clone URL.");
  const snapshot = await getProjectRepoSnapshot({
    cloneUrl: file.url,
    defaultBranch: file.branch,
    baseBranch: file.branch,
  });
  const base = snapshot.latestCommit?.hash;
  if (!base) throw new Error(`The branch ${file.branch} has no commit.`);
  const content = await getProjectRepoFileContent({
    cloneUrl: file.url,
    defaultBranch: file.branch,
    targetCommit: base,
    path: file.path,
  });
  if (content === null) {
    throw new Error(
      `${file.path} is missing, binary, or larger than 64 KiB at ${base.slice(0, 7)}.`,
    );
  }
  return { base, content };
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
