const MAX_EXPANDED_MESSAGES = 500;
const expandedMessageIds = new Set<string>();

export function isMessageFoldExpanded(messageId: string): boolean {
  return expandedMessageIds.has(messageId);
}

export function setMessageFoldExpanded(messageId: string, expanded: boolean) {
  expandedMessageIds.delete(messageId);
  if (!expanded) return;
  expandedMessageIds.add(messageId);
  if (expandedMessageIds.size > MAX_EXPANDED_MESSAGES) {
    const oldest = expandedMessageIds.values().next().value;
    if (oldest !== undefined) expandedMessageIds.delete(oldest);
  }
}

export function resetMessageFoldState() {
  expandedMessageIds.clear();
}
