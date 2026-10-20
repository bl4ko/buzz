import * as React from "react";

import { MARKDOWN_FLOW_CLASS } from "../markdownUtils";
import {
  isMessageFoldExpanded,
  setMessageFoldExpanded,
} from "./messageFoldState";

export const MESSAGE_FOLD_LINES = 8;

const FOLD_MEDIA_SELECTOR =
  "img:not([data-custom-emoji]), video, audio, iframe, [data-file-card]";

const FOLD_FADE =
  "linear-gradient(to bottom, black calc(100% - 2rem), transparent)";

function foldLimitPx(element: HTMLElement): number {
  const style = window.getComputedStyle(element);
  const lineHeight = Number.parseFloat(style.lineHeight);
  if (Number.isFinite(lineHeight) && lineHeight > 0) {
    return lineHeight * MESSAGE_FOLD_LINES;
  }
  const fontSize = Number.parseFloat(style.fontSize);
  return (
    (Number.isFinite(fontSize) && fontSize > 0 ? fontSize : 14) *
    1.25 *
    MESSAGE_FOLD_LINES
  );
}

type MessageFoldProps = {
  children: React.ReactNode;
  foldId?: string;
  forceExpanded?: boolean;
};

export function MessageFold({
  children,
  foldId,
  forceExpanded = false,
}: MessageFoldProps) {
  const clipId = React.useId();
  const contentRef = React.useRef<HTMLDivElement | null>(null);
  const [expanded, setExpanded] = React.useState(
    () => forceExpanded || (foldId ? isMessageFoldExpanded(foldId) : false),
  );
  const [limit, setLimit] = React.useState<number | null>(null);

  React.useEffect(() => {
    if (forceExpanded) setExpanded(true);
  }, [forceExpanded]);

  React.useLayoutEffect(() => {
    const content = contentRef.current;
    if (!content) return;
    const measure = () => {
      const next =
        content.querySelector(FOLD_MEDIA_SELECTOR) === null &&
        content.offsetHeight > foldLimitPx(content) + 1
          ? foldLimitPx(content)
          : null;
      setLimit((current) => (current === next ? current : next));
    };
    measure();
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(measure);
    observer.observe(content);
    return () => observer.disconnect();
  }, []);

  const folded = limit !== null && !expanded;

  return (
    <div
      data-message-fold={
        limit === null ? undefined : folded ? "folded" : "expanded"
      }
    >
      <div
        data-testid="message-fold-clip"
        id={clipId}
        style={
          folded
            ? {
                maxHeight: `${limit}px`,
                overflow: "hidden",
                maskImage: FOLD_FADE,
                WebkitMaskImage: FOLD_FADE,
              }
            : undefined
        }
      >
        <div className={MARKDOWN_FLOW_CLASS} ref={contentRef}>
          {children}
        </div>
      </div>
      {limit !== null ? (
        <button
          aria-controls={clipId}
          aria-expanded={!folded}
          className="mt-1 rounded-sm text-sm font-medium text-primary hover:underline focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring"
          data-testid="message-fold-toggle"
          onClick={(event) => {
            event.stopPropagation();
            if (foldId) setMessageFoldExpanded(foldId, folded);
            setExpanded(folded);
          }}
          type="button"
        >
          {folded ? "Show more" : "Show less"}
        </button>
      ) : null}
    </div>
  );
}
