import type { CSSProperties } from "react";

import { cn } from "@/shared/lib/cn";
import { useOlympusId } from "./OlympusMark";

const KEY = "M2,14 V2 H14 V14 H6 V6 H10 V10";
const RING = [
  [0, 0, 0],
  [1, 0, 0],
  [2, 0, 90],
  [2, 1, 90],
  [2, 2, 180],
  [1, 2, 180],
  [0, 2, 270],
  [0, 1, 270],
];

const SMALL_KEYS = [
  [12, 5, "M0.5,5V0.5H4.5V4.5H2.5V2"],
  [16, 7, "M0.5,7V0.5H6.5V6.5H2.5V2.5H4.5V5"],
  [20, 9, "M0.5,9V0.5H8.5V8.5H3.5V3.5H5.5V6"],
] as const;
const SQUARE = [
  [0, 0],
  [1, 0],
  [1, 1],
  [0, 1],
];

export function OlympusBoltSpinner({
  className,
  label,
  style,
}: {
  className?: string;
  label?: string;
  style?: CSSProperties;
}) {
  const id = useOlympusId();
  const art = (
    <svg aria-hidden="true" viewBox="0 0 48 48">
      <filter height="220%" id={id} width="220%" x="-60%" y="-60%">
        <feGaussianBlur stdDeviation="1.3" />
      </filter>
      {RING.map(([column, row, turn], index) => (
        <g
          key={`${column}-${row}`}
          style={{ animationDelay: `${index * 0.2 - 1.6}s` }}
          transform={`translate(${column * 16} ${row * 16}) rotate(${turn} 8 8)`}
        >
          <path className="olympus-bolt__glow" d={KEY} filter={`url(#${id})`} />
          <path className="olympus-bolt__tile" d={KEY} />
        </g>
      ))}
    </svg>
  );

  return label ? (
    <span
      aria-label={label}
      className={cn("olympus-bolt", className)}
      role="img"
      style={style}
    >
      {art}
    </span>
  ) : (
    <span
      aria-hidden="true"
      className={cn("olympus-bolt", className)}
      style={style}
    >
      {art}
    </span>
  );
}

export function OlympusPuffs() {
  return SMALL_KEYS.map(([size, tile, d]) => (
    <svg
      aria-hidden="true"
      className={`olympus-inline olympus-inline--${size}`}
      key={size}
      viewBox={`0 0 ${size} ${size}`}
    >
      {SQUARE.map(([column, row], index) => (
        <g
          key={`${column}-${row}`}
          style={{ animationDelay: `${index * 0.3 - 1.2}s` }}
          transform={`translate(${column * (size - tile)} ${row * (size - tile)}) rotate(${index * 90} ${tile / 2} ${tile / 2})`}
        >
          <path className="olympus-inline__tile" d={d} />
          <path className="olympus-inline__hot" d={d} />
        </g>
      ))}
    </svg>
  ));
}
