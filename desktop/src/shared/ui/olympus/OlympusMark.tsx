import { useId } from "react";

import { cn } from "@/shared/lib/cn";
import {
  OLYMPUS_CLOUD_BACK,
  OLYMPUS_CLOUD_FRONT,
  OLYMPUS_FACET_BRIGHT,
  OLYMPUS_FACET_DARK,
  OLYMPUS_FACET_MID,
  OLYMPUS_GRADIENTS,
  OLYMPUS_MARK_VIEW_BOX,
  OLYMPUS_MOUNTAIN_LIT,
  OLYMPUS_MOUNTAIN_SHADE,
  OLYMPUS_RING,
  OLYMPUS_SNOW_LIT,
  OLYMPUS_SNOW_SHADE,
  OLYMPUS_SPINE,
} from "./olympusArt";

export function useOlympusId() {
  return `olympus-${useId().replace(/[^a-zA-Z0-9_-]/g, "")}`;
}

export function OlympusDefs({ id }: { id: string }) {
  return (
    <defs>
      <radialGradient
        cx="512"
        cy="372"
        gradientUnits="userSpaceOnUse"
        id={`${id}-disc`}
        r="400"
      >
        <stop offset="0" stopColor="#7A6CF2" />
        <stop offset=".45" stopColor="#3E40B0" />
        <stop offset="1" stopColor="#151C56" />
      </radialGradient>
      {Object.entries(OLYMPUS_GRADIENTS).map(([name, [box, ...stops]]) => {
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
            {stops.map((stop) => {
              const [offset, color] = stop.split(" ");
              return <stop key={stop} offset={offset} stopColor={color} />;
            })}
          </linearGradient>
        );
      })}
      <filter height="220%" id={`${id}-glow`} width="220%" x="-60%" y="-60%">
        <feGaussianBlur stdDeviation="30" />
      </filter>
      <clipPath id={`${id}-clip`}>
        <circle {...OLYMPUS_RING} />
      </clipPath>
    </defs>
  );
}

export function OlympusMountain({ id }: { id: string }) {
  return (
    <>
      <polygon fill={`url(#${id}-lit)`} points={OLYMPUS_MOUNTAIN_LIT} />
      <polygon fill={`url(#${id}-shade)`} points={OLYMPUS_MOUNTAIN_SHADE} />
      <polygon fill="#22327E" opacity=".55" points={OLYMPUS_FACET_DARK} />
      <polygon fill="#B4C3FF" opacity=".34" points={OLYMPUS_FACET_BRIGHT} />
      <polygon fill="#4257B0" opacity=".34" points={OLYMPUS_FACET_MID} />
      <polyline
        fill="none"
        opacity=".55"
        points={OLYMPUS_SPINE}
        stroke="#E6ECFF"
        strokeLinejoin="round"
        strokeWidth="4"
      />
      <polygon fill={`url(#${id}-snow)`} points={OLYMPUS_SNOW_LIT} />
      <polygon fill={`url(#${id}-snowsh)`} points={OLYMPUS_SNOW_SHADE} />
    </>
  );
}

export function OlympusCloud({ back, id }: { back?: boolean; id: string }) {
  const d = back ? OLYMPUS_CLOUD_BACK : OLYMPUS_CLOUD_FRONT;

  return (
    <>
      <path d={d} fill={back ? "#B7C2F8" : "#FFFFFF"} />
      <path
        d={d}
        fill={`url(#${id}-cloud${back ? "b" : "f"})`}
        transform="translate(0 7)"
      />
    </>
  );
}

export function OlympusRing({ id }: { id: string }) {
  return (
    <g fill="none">
      <circle {...OLYMPUS_RING} stroke={`url(#${id}-ring)`} strokeWidth="68" />
      <circle
        {...OLYMPUS_RING}
        opacity=".7"
        r="375"
        stroke="#FFF6C8"
        strokeWidth="3"
      />
      <circle
        {...OLYMPUS_RING}
        opacity=".55"
        r="313"
        stroke="#8A4B06"
        strokeWidth="5"
      />
    </g>
  );
}

export function OlympusMark({ className }: { className?: string }) {
  const id = useOlympusId();

  return (
    <svg
      aria-hidden="true"
      className={cn("olympus-mark", className)}
      viewBox={OLYMPUS_MARK_VIEW_BOX}
    >
      <OlympusDefs id={id} />
      <circle {...OLYMPUS_RING} fill={`url(#${id}-disc)`} r="314" />
      <g clipPath={`url(#${id}-clip)`}>
        <OlympusMountain id={id} />
        <OlympusCloud back id={id} />
        <OlympusCloud id={id} />
      </g>
      <circle
        {...OLYMPUS_RING}
        fill="none"
        filter={`url(#${id}-glow)`}
        opacity=".5"
        stroke="#FFAE1A"
        strokeWidth="68"
      />
      <OlympusRing id={id} />
    </svg>
  );
}

export function OlympusGlyph({ className }: { className?: string }) {
  const id = useOlympusId();

  return (
    <svg
      aria-hidden="true"
      className={cn("olympus-glyph", className)}
      fill="currentColor"
      viewBox={OLYMPUS_MARK_VIEW_BOX}
    >
      <clipPath id={`${id}-disc`}>
        <circle {...OLYMPUS_RING} r="284" />
      </clipPath>
      <circle
        {...OLYMPUS_RING}
        fill="none"
        stroke="currentColor"
        strokeWidth="68"
      />
      <polygon clipPath={`url(#${id}-disc)`} points="130,940 512,236 894,940" />
    </svg>
  );
}
