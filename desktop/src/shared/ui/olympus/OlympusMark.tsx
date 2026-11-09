import { useId } from "react";

import { cn } from "@/shared/lib/cn";
import {
  OLYMPUS_BOLT,
  OLYMPUS_COLORS,
  OLYMPUS_MARK_VIEW_BOX,
  OLYMPUS_MOUNTAIN,
  OLYMPUS_SHADE,
  OLYMPUS_SNOW,
} from "./olympusArt";

export function OlympusMark({ className }: { className?: string }) {
  return (
    <svg
      aria-hidden="true"
      className={cn("olympus-mark", className)}
      viewBox={OLYMPUS_MARK_VIEW_BOX}
    >
      <polygon fill={OLYMPUS_COLORS.mountain} points={OLYMPUS_MOUNTAIN} />
      <polygon fill={OLYMPUS_COLORS.mountainShade} points={OLYMPUS_SHADE} />
      <polygon fill={OLYMPUS_COLORS.marble} points={OLYMPUS_SNOW} />
      <polygon fill={OLYMPUS_COLORS.gold} points={OLYMPUS_BOLT} />
    </svg>
  );
}

export function OlympusGlyph({ className }: { className?: string }) {
  const maskId = `olympus-glyph-${useId().replace(/[^a-zA-Z0-9_-]/g, "")}`;

  return (
    <svg
      aria-hidden="true"
      className={cn("olympus-glyph", className)}
      fill="currentColor"
      viewBox={OLYMPUS_MARK_VIEW_BOX}
    >
      <defs>
        <mask
          id={maskId}
          maskUnits="userSpaceOnUse"
          x="0"
          y="0"
          width="1024"
          height="1024"
        >
          <rect width="1024" height="1024" fill="#fff" />
          <polygon
            fill="#000"
            points={OLYMPUS_BOLT}
            stroke="#000"
            strokeLinejoin="round"
            strokeWidth="80"
          />
        </mask>
      </defs>
      <polygon mask={`url(#${maskId})`} points={OLYMPUS_MOUNTAIN} />
      <polygon points={OLYMPUS_BOLT} />
    </svg>
  );
}
