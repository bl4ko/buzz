import type { CSSProperties } from "react";

import { cn } from "@/shared/lib/cn";
import { useOlympusId } from "./OlympusMark";
import {
  OLYMPUS_BOLT,
  OLYMPUS_BOLT_FOLD,
  OLYMPUS_BOLT_SEGMENTS,
  OLYMPUS_INLINE_VIEW_BOX,
  OLYMPUS_LOADER_BOLT_TRANSFORM,
  OLYMPUS_LOADER_VIEW_BOX,
  OLYMPUS_RING,
} from "./olympusArt";

const THEMED_GRADIENTS = {
  ring: ["150 110 870 830", "0", ".35", ".6", ".7", "1"],
  left: ["0 56 0 628", "0", ".6", "1"],
  right: ["0 56 0 628", "0", ".5", "1"],
};

const COMET = [
  [110, 0.22],
  [66, 0.5],
  [26, 1],
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
    <>
      <svg
        aria-hidden="true"
        className="olympus-bolt__track"
        viewBox={OLYMPUS_LOADER_VIEW_BOX}
      >
        <defs>
          {Object.entries(THEMED_GRADIENTS).map(([name, [box, ...offsets]]) => {
            const [x1, y1, x2, y2] = box.split(" ");
            return (
              <linearGradient
                gradientUnits="userSpaceOnUse"
                id={`${id}-${name}`}
                key={name}
                x1={x1}
                x2={x2}
                y1={y1}
                y2={y2}
              >
                {offsets.map((offset, index) => (
                  <stop
                    key={offset}
                    offset={offset}
                    style={{
                      stopColor: `var(--olympus-${name}-${index + 1})`,
                    }}
                  />
                ))}
              </linearGradient>
            );
          })}
          <filter
            height="220%"
            id={`${id}-glow`}
            width="220%"
            x="-60%"
            y="-60%"
          >
            <feGaussianBlur stdDeviation="30" />
          </filter>
        </defs>
        <circle {...OLYMPUS_RING} fill="none" strokeWidth="56" />
      </svg>
      <svg
        aria-hidden="true"
        className="olympus-bolt__comet"
        viewBox={OLYMPUS_LOADER_VIEW_BOX}
      >
        {COMET.map(([sweep, opacity]) => (
          <circle
            {...OLYMPUS_RING}
            fill="none"
            key={sweep}
            opacity={opacity}
            pathLength="360"
            stroke={`url(#${id}-ring)`}
            strokeDasharray={`${sweep} ${360 - sweep}`}
            strokeLinecap={opacity === 1 ? "round" : undefined}
            strokeWidth="56"
            transform={`rotate(${-sweep} 512 468)`}
          />
        ))}
      </svg>
      <span className="olympus-bolt__punch">
        <svg
          aria-hidden="true"
          className="olympus-bolt__glow"
          viewBox={OLYMPUS_LOADER_VIEW_BOX}
        >
          <polygon
            fill="#FFB21C"
            filter={`url(#${id}-glow)`}
            points={OLYMPUS_BOLT}
            transform={OLYMPUS_LOADER_BOLT_TRANSFORM}
          />
        </svg>
        <svg aria-hidden="true" viewBox={OLYMPUS_LOADER_VIEW_BOX}>
          <g transform={OLYMPUS_LOADER_BOLT_TRANSFORM}>
            <polygon fill={`url(#${id}-left)`} points={OLYMPUS_BOLT} />
            <polygon fill={`url(#${id}-right)`} points={OLYMPUS_BOLT_FOLD} />
          </g>
        </svg>
        <svg
          aria-hidden="true"
          className="olympus-bolt__flash"
          viewBox={OLYMPUS_LOADER_VIEW_BOX}
        >
          <polygon
            points={OLYMPUS_BOLT}
            transform={OLYMPUS_LOADER_BOLT_TRANSFORM}
          />
        </svg>
      </span>
    </>
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
  return (
    <svg
      aria-hidden="true"
      className="olympus-inline"
      viewBox={OLYMPUS_INLINE_VIEW_BOX}
    >
      {OLYMPUS_BOLT_SEGMENTS.map((points) => (
        <polygon key={points} points={points} />
      ))}
    </svg>
  );
}
