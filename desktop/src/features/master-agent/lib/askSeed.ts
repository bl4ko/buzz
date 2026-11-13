import { buildMessageLink } from "@/features/messages/lib/messageLink";
import type { AskMasterSeed } from "./masterAgent";

const COMPOSER_SELECTOR = '[data-testid="message-input"]';

function elementOf(node: Node | null): Element | null {
  if (!node) return null;
  return node.nodeType === 1 ? (node as Element) : node.parentElement;
}

export function selectionSeed(
  selection: Selection | null,
  channelId: string | null,
): AskMasterSeed | null {
  if (!selection || selection.isCollapsed) return null;
  const text = selection.toString();
  if (!text.trim()) return null;
  const element = elementOf(selection.anchorNode);
  if (!element || element.closest('[contenteditable="true"]')) return null;
  const row = element.closest<HTMLElement>("[data-message-id]");
  const messageId = row?.dataset.messageId;
  if (!messageId) return null;
  return {
    quote: text,
    link: channelId ? buildMessageLink({ channelId, messageId }) : null,
  };
}

export function composerSeed(doc: Document): AskMasterSeed | null {
  const active = elementOf(doc.activeElement)?.closest(COMPOSER_SELECTOR);
  const editor = active ?? doc.querySelector(COMPOSER_SELECTOR);
  const text =
    editor instanceof HTMLElement
      ? (editor.innerText ?? editor.textContent ?? "")
      : "";
  return text.trim() ? { quote: text } : null;
}

export function focusComposer(doc: Document) {
  const editor = doc.querySelector(COMPOSER_SELECTOR);
  if (editor instanceof HTMLElement) editor.focus();
}
