export type OlympusOwned = {
  managedBy: string | null;
  gitopsFields: readonly string[] | null;
};

export function olympusOwnershipKnown(owned: OlympusOwned): boolean {
  return owned.gitopsFields !== null;
}

export function olympusFieldLocked(owned: OlympusOwned, path: string): boolean {
  if (owned.gitopsFields === null) return owned.managedBy === "gitops";
  return owned.gitopsFields.some(
    (field) =>
      field === path ||
      field.startsWith(`${path}.`) ||
      path.startsWith(`${field}.`),
  );
}

export function olympusLockedPaths(
  owned: OlympusOwned,
  patch: Record<string, unknown>,
  prefix = "spec",
): string[] {
  return Object.keys(patch)
    .map((key) => `${prefix}.${key}`)
    .filter((path) => olympusFieldLocked(owned, path));
}

export function olympusCanDelete(owned: OlympusOwned): boolean {
  return owned.managedBy !== "gitops";
}
