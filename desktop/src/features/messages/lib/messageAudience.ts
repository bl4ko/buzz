/** Presentation intent only: channel ACLs, mentions and thread routing are unchanged. */
export type MessageAudience = "agents" | "everyone";

/** Unknown, missing or ambiguous declarations retain legacy visibility. */
export function messageAudience(
  tags: readonly string[][] = [],
): MessageAudience | null {
  const declarations = tags.filter((tag) => tag[0] === "audience");
  if (declarations.length !== 1 || declarations[0].length !== 2) return null;
  const value = declarations[0][1];
  return value === "agents" || value === "everyone" ? value : null;
}

export function isAgentCoordination(message: {
  kind?: number;
  tags?: string[][];
}): boolean {
  return (
    (message.kind === 9 || message.kind === 45001 || message.kind === 45003) &&
    messageAudience(message.tags) === "agents"
  );
}
