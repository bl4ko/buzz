import { type CSSProperties, type RefObject, useEffect, useRef } from "react";

import { cn } from "@/shared/lib/cn";
import {
  OlympusDefs,
  OlympusMountain,
  OlympusRing,
  useOlympusId,
} from "./OlympusMark";
import {
  OLYMPUS_BOLTS,
  OLYMPUS_DISC_RIDGE,
  OLYMPUS_DISC_STARS,
  OLYMPUS_DISC_VIEW_BOX,
  OLYMPUS_DISTANT,
  OLYMPUS_FLICKERS,
  OLYMPUS_MEANDER,
  OLYMPUS_RIM_LEFT,
  OLYMPUS_RIM_RIGHT,
  OLYMPUS_RING,
  OLYMPUS_RULE,
  OLYMPUS_SEAL_CLOUDS,
  OLYMPUS_SEAL_SCHEDULE,
  OLYMPUS_SEAL_VIEW_BOX,
  OLYMPUS_SHEETS,
  OLYMPUS_SKY_CLOUDS,
  OLYMPUS_SKY_SCHEDULE,
  OLYMPUS_SKY_VIEW_BOX,
  OLYMPUS_SNOW_LIT,
  OLYMPUS_SNOW_SHADE,
  OLYMPUS_STARS,
  OLYMPUS_STORM_VIEW_BOX,
  OLYMPUS_TWINKLERS,
  type OlympusCloudArt,
  type OlympusSchedule,
} from "./olympusArt";

const FACE_VIEW_BOX = "112 68 800 800";

const WISPS = [
  [
    "a",
    [
      [-1.5, -0.2, 1.5, 0.068, 0.34, "50%"],
      [1.7, 0.5, 1.4, 0.063, 0.3, "50%"],
    ],
  ],
  ["b", [[0, 0.62, 1.7, 0.079, 0.7, "0%"]]],
  ["c", [[0, -0.5, 1.2, 0.058, 0.5, "0%"]]],
] as const;

function useLightning(
  ref: RefObject<HTMLElement | null>,
  schedule: OlympusSchedule,
) {
  useEffect(() => {
    const scene = ref.current;
    if (
      !scene ||
      window.matchMedia("(prefers-reduced-motion: reduce)").matches
    ) {
      return;
    }

    const timers = new Map<string, number>();
    const arm = (id: string, delay: number, period: number) => {
      timers.set(
        id,
        window.setTimeout(() => {
          for (const layer of scene.querySelectorAll(`[data-strike="${id}"]`)) {
            for (const animation of layer.getAnimations({ subtree: true })) {
              animation.currentTime = 0;
              animation.play();
            }
          }
          arm(id, period, period);
        }, delay),
      );
    };
    const start = () => {
      for (const [id, first, period] of schedule) arm(id, first, period);
    };
    const stop = () => {
      for (const timer of timers.values()) window.clearTimeout(timer);
    };
    const onVisibilityChange = () => {
      stop();
      if (!document.hidden) start();
    };

    start();
    document.addEventListener("visibilitychange", onVisibilityChange);
    return () => {
      stop();
      document.removeEventListener("visibilitychange", onVisibilityChange);
    };
  }, [ref, schedule]);
}

const SKY = [0, 0, 1440, 900];
const FACE = [112, 68, 800, 800];
const STORM = [200, 156, 624, 624];

function place(
  [x, y, width, height]: readonly number[],
  [left, top, across, down]: number[],
): CSSProperties {
  return {
    height: `${(height / down) * 100}%`,
    left: `${((x - left) / across) * 100}%`,
    top: `${((y - top) / down) * 100}%`,
    width: `${(width / across) * 100}%`,
  };
}

function Cloud({
  art,
  className,
  id,
  style,
  viewBox,
}: {
  art: OlympusCloudArt;
  className: string;
  id: string;
  style?: CSSProperties;
  viewBox: string;
}) {
  const base = art.stops[art.stops.length - 1].split(" ")[1];
  const lobes = (dx: number, dy: number, scale: number, lift = 0) =>
    art.lobes.split(" ").map((lobe) => {
      const [x, y, r] = lobe.split(",").map(Number);
      return (
        <circle
          cx={x + r * dx}
          cy={y + r * dy - lift}
          key={lobe}
          r={r * scale}
        />
      );
    });

  return (
    <svg
      aria-hidden="true"
      className={className}
      style={style}
      viewBox={viewBox}
    >
      <defs>
        <linearGradient
          gradientUnits="userSpaceOnUse"
          id={`${id}-fill`}
          x1="0"
          x2="0"
          y1={art.top}
          y2={art.bottom}
        >
          {art.stops.map((stop) => {
            const [offset, color] = stop.split(" ");
            return <stop key={stop} offset={offset} stopColor={color} />;
          })}
        </linearGradient>
        <linearGradient
          gradientUnits="userSpaceOnUse"
          id={`${id}-fade`}
          x1="0"
          x2="0"
          y1={art.fade}
          y2={art.bottom}
        >
          <stop offset="0" stopColor={base} stopOpacity="0" />
          <stop offset="1" stopColor={base} />
        </linearGradient>
        <radialGradient id={`${id}-light`}>
          <stop offset="0" stopColor={art.light} stopOpacity=".6" />
          <stop offset=".55" stopColor={art.light} stopOpacity=".22" />
          <stop offset="1" stopColor={art.light} stopOpacity="0" />
        </radialGradient>
        <radialGradient id={`${id}-dark`}>
          <stop offset="0" stopColor={art.dark} stopOpacity=".55" />
          <stop offset=".6" stopColor={art.dark} stopOpacity=".2" />
          <stop offset="1" stopColor={art.dark} stopOpacity="0" />
        </radialGradient>
      </defs>
      <g fill={art.rim}>{lobes(0, 0, 1, art.lift)}</g>
      <g fill={`url(#${id}-fill)`}>
        <polygon points={art.body} />
        {lobes(0, 0, 1)}
      </g>
      <g fill={`url(#${id}-dark)`}>{lobes(0.12, 0.62, 0.95)}</g>
      <g fill={`url(#${id}-light)`}>{lobes(-0.16, -0.3, 0.78)}</g>
      <rect
        fill={`url(#${id}-fade)`}
        height="900"
        width="2600"
        x="-580"
        y={art.fade}
      />
    </svg>
  );
}

function SkyCloud({ id, name }: { id: string; name: string }) {
  const art = OLYMPUS_SKY_CLOUDS[name];
  const edge = art.top - art.lift - 2;

  return (
    <div className={`olympus-rise olympus-rise--${name} olympus-in`}>
      <Cloud
        art={art}
        className={`olympus-cloud olympus-cloud--${name}`}
        id={`${id}-${name}`}
        style={place([0, edge, 1440, 900 - edge], SKY)}
        viewBox={`0 ${edge} 1440 ${900 - edge}`}
      />
    </div>
  );
}

export function OlympusSky() {
  const id = useOlympusId();
  const ref = useRef<HTMLDivElement>(null);
  useLightning(ref, OLYMPUS_SKY_SCHEDULE);

  return (
    <div
      aria-hidden="true"
      className="olympus-sky pointer-events-none absolute inset-0 overflow-hidden"
      data-testid="olympus-sky"
      ref={ref}
    >
      <div className="olympus-sky__gradient olympus-in" />
      <div className="olympus-sky__art">
        <div className="olympus-sky__stars olympus-in">
          <svg aria-hidden="true" fill="#EEF2FF" viewBox={OLYMPUS_SKY_VIEW_BOX}>
            {OLYMPUS_STARS.split(" ").map((star) => {
              const [x, y, r, opacity] = star.split(",");
              return (
                <circle cx={x} cy={y} key={star} opacity={opacity} r={r} />
              );
            })}
          </svg>
          {OLYMPUS_TWINKLERS.map(([x, y, r, period, phase]) => (
            <i
              className="olympus-star"
              key={`${x}-${y}`}
              style={{
                ...place([x - r, y - r, r * 2, r * 2], SKY),
                animationDelay: `-${phase}s`,
                animationDuration: `${period}s`,
              }}
            />
          ))}
        </div>
        <SkyCloud id={id} name="back" />
        {OLYMPUS_SHEETS.map(([strike, x, y, r]) => (
          <div
            className="olympus-sheet"
            data-strike={strike}
            key={strike}
            style={place([x - r, y - r, r * 2, r * 2], SKY)}
          />
        ))}
        <SkyCloud id={id} name="mid" />
        {OLYMPUS_DISTANT.map((strike) => (
          <svg
            aria-hidden="true"
            className="olympus-distant"
            data-strike={strike.id}
            key={strike.id}
            style={place(strike.box, SKY)}
            viewBox={strike.box.join(" ")}
          >
            <filter
              height="200%"
              id={`${id}-${strike.id}`}
              width="200%"
              x="-50%"
              y="-50%"
            >
              <feGaussianBlur stdDeviation="3" />
            </filter>
            {strike.strokes.map(([points, width]) => (
              <polyline
                filter={`url(#${id}-${strike.id})`}
                key={points}
                points={points}
                stroke="#B9C2FF"
                strokeOpacity=".5"
                strokeWidth={width * 3.6}
              />
            ))}
            {strike.strokes.map(([points, width]) => (
              <polyline
                className="olympus-draw"
                key={points}
                pathLength="1"
                points={points}
                stroke="#FFFFFF"
                strokeWidth={width}
                style={{ animationDuration: "70ms" }}
              />
            ))}
          </svg>
        ))}
        <div className="olympus-sky__ground">
          <SkyCloud id={id} name="front" />
          <div className="olympus-rise olympus-rise--base olympus-in">
            <div className="olympus-sky__shade" />
          </div>
        </div>
      </div>
    </div>
  );
}

function Bolt({
  bolt,
  id,
}: {
  bolt: (typeof OLYMPUS_BOLTS)[number];
  id: string;
}) {
  const near = bolt.right ? OLYMPUS_RIM_RIGHT : OLYMPUS_RIM_LEFT;
  const far = bolt.right ? OLYMPUS_RIM_LEFT : OLYMPUS_RIM_RIGHT;
  const nearSnow = bolt.right ? OLYMPUS_SNOW_SHADE : OLYMPUS_SNOW_LIT;
  const farSnow = bolt.right ? OLYMPUS_SNOW_LIT : OLYMPUS_SNOW_SHADE;

  return {
    back: (
      <svg
        aria-hidden="true"
        className="olympus-flash"
        data-strike={bolt.id}
        key={`${bolt.id}-back`}
        viewBox={OLYMPUS_STORM_VIEW_BOX}
      >
        <circle
          cx={bolt.glow[0]}
          cy={bolt.glow[1]}
          fill={`url(#${id}-back)`}
          r="250"
        />
        <circle {...OLYMPUS_RING} fill="#A9A0FF" opacity=".3" r="312" />
      </svg>
    ),
    strike: (
      <svg
        aria-hidden="true"
        className="olympus-strike"
        data-strike={bolt.id}
        key={bolt.id}
        viewBox={OLYMPUS_STORM_VIEW_BOX}
      >
        <polyline
          filter={`url(#${id}-z20)`}
          opacity=".38"
          points={bolt.strokes[0][0]}
          stroke="#9E92FF"
          strokeWidth="55"
        />
        <g filter={`url(#${id}-z9)`} stroke="#CFC6FF" strokeOpacity=".5">
          {bolt.strokes.map(([points, width]) => (
            <polyline key={points} points={points} strokeWidth={width * 3.4} />
          ))}
        </g>
        <g filter={`url(#${id}-z4)`} stroke="#FFF3DA" strokeOpacity=".55">
          {bolt.strokes.slice(0, 3).map(([points, width]) => (
            <polyline key={points} points={points} strokeWidth={width * 1.9} />
          ))}
        </g>
        {bolt.strokes.map(([points, width, start, end]) => (
          <polyline
            className="olympus-draw"
            key={points}
            pathLength="1"
            points={points}
            stroke="#FFFDF0"
            strokeWidth={width}
            style={{
              animationDuration: `${end}ms`,
              strokeDashoffset: end / (end - start),
            }}
          />
        ))}
      </svg>
    ),
    front: (
      <svg
        aria-hidden="true"
        className="olympus-flash"
        data-strike={bolt.id}
        key={`${bolt.id}-front`}
        viewBox={OLYMPUS_DISC_VIEW_BOX}
      >
        <polyline opacity=".9" points={near} stroke="#E9EAFF" strokeWidth="5" />
        <polygon fill="#F4F3FF" opacity=".6" points={nearSnow} />
        <polyline opacity=".5" points={far} stroke="#E9EAFF" strokeWidth="4" />
        <polygon fill="#F4F3FF" opacity=".3" points={farSnow} />
      </svg>
    ),
    ring: (
      <svg
        aria-hidden="true"
        className="olympus-flash"
        data-strike={bolt.id}
        key={`${bolt.id}-ring`}
        viewBox={FACE_VIEW_BOX}
      >
        <circle
          {...OLYMPUS_RING}
          fill="none"
          opacity=".8"
          r="314"
          stroke="#F1EEFF"
          strokeWidth="9"
        />
        <circle
          {...OLYMPUS_RING}
          fill="none"
          opacity=".16"
          stroke="#F4F2FF"
          strokeWidth="68"
        />
      </svg>
    ),
  };
}

function Seal({ id }: { id: string }) {
  const bolts = OLYMPUS_BOLTS.map((bolt) => Bolt({ bolt, id }));

  return (
    <div className="olympus-seal olympus-in">
      <svg
        aria-hidden="true"
        className="olympus-seal__halo"
        viewBox={OLYMPUS_SEAL_VIEW_BOX}
      >
        <circle
          {...OLYMPUS_RING}
          fill="none"
          filter={`url(#${id}-glow)`}
          stroke="#FFAE1A"
          strokeWidth="68"
        />
      </svg>
      <div className="olympus-seal__face">
        <svg aria-hidden="true" viewBox={FACE_VIEW_BOX}>
          <OlympusDefs id={id} />
          <defs>
            {[4, 9, 20].map((blur) => (
              <filter
                filterUnits="userSpaceOnUse"
                height="1024"
                id={`${id}-z${blur}`}
                key={blur}
                width="1024"
                x="0"
                y="0"
              >
                <feGaussianBlur stdDeviation={blur} />
              </filter>
            ))}
            <radialGradient id={`${id}-back`}>
              <stop offset="0" stopColor="#F1EEFF" stopOpacity=".62" />
              <stop offset=".35" stopColor="#B9B0FF" stopOpacity=".32" />
              <stop offset="1" stopColor="#8E86FF" stopOpacity="0" />
            </radialGradient>
          </defs>
          <circle {...OLYMPUS_RING} fill={`url(#${id}-disc)`} r="314" />
        </svg>
        {OLYMPUS_DISC_STARS.map(([x, y, r, period]) => (
          <i
            className="olympus-star olympus-star--disc"
            key={`${x}-${y}`}
            style={{
              ...place([x - r, y - r, r * 2, r * 2], FACE),
              animationDuration: `${period}s`,
            }}
          />
        ))}
        <div className="olympus-seal__disc">
          <div className="olympus-seal__storm">
            {bolts.flatMap((bolt) => [bolt.back, bolt.strike])}
            {OLYMPUS_FLICKERS.map(([strike, x, y, r]) => (
              <div
                className="olympus-flicker"
                data-strike={strike}
                key={strike}
                style={place([x - r, y - r, r * 2, r * 2], STORM)}
              />
            ))}
          </div>
          <svg
            aria-hidden="true"
            className="olympus-drift olympus-drift--ridge"
            viewBox={OLYMPUS_DISC_VIEW_BOX}
          >
            <polygon fill="#2A3690" opacity=".75" points={OLYMPUS_DISC_RIDGE} />
          </svg>
          <svg aria-hidden="true" viewBox={OLYMPUS_DISC_VIEW_BOX}>
            <OlympusMountain id={id} />
          </svg>
          {bolts.map((bolt) => bolt.front)}
          <Cloud
            art={OLYMPUS_SEAL_CLOUDS.back}
            className="olympus-drift olympus-drift--back"
            id={`${id}-inner-back`}
            viewBox={OLYMPUS_DISC_VIEW_BOX}
          />
          <Cloud
            art={OLYMPUS_SEAL_CLOUDS.front}
            className="olympus-drift olympus-drift--front"
            id={`${id}-inner-front`}
            viewBox={OLYMPUS_DISC_VIEW_BOX}
          />
        </div>
        <svg aria-hidden="true" viewBox={FACE_VIEW_BOX}>
          <OlympusRing id={id} />
        </svg>
        <svg
          aria-hidden="true"
          className="olympus-seal__meander"
          viewBox={FACE_VIEW_BOX}
        >
          <path
            d={OLYMPUS_MEANDER}
            fill="none"
            opacity=".82"
            stroke="#7E4505"
            strokeWidth="7"
          />
        </svg>
        {bolts.map((bolt) => bolt.ring)}
      </div>
    </div>
  );
}

function Wisps({ names }: { names: string[] }) {
  return (
    <div className="olympus-hero__wisps olympus-in">
      {WISPS.filter(([name]) => names.includes(name)).map(([name, bands]) => (
        <div className={`olympus-wisp olympus-wisp--${name}`} key={name}>
          {bands.map(([dx, dy, rx, ry, opacity, anchor]) => (
            <i
              key={dx}
              style={{
                height: `calc(${ry * 2} * var(--olympus-r))`,
                left: `calc(${anchor} + ${dx - rx} * var(--olympus-r))`,
                opacity,
                top: `calc(50% + ${dy - ry} * var(--olympus-r))`,
                width: `calc(${rx * 2} * var(--olympus-r))`,
              }}
            />
          ))}
        </div>
      ))}
    </div>
  );
}

export function OlympusHero({ className }: { className?: string }) {
  const id = useOlympusId();
  const ref = useRef<HTMLDivElement>(null);
  useLightning(ref, OLYMPUS_SEAL_SCHEDULE);

  return (
    <div
      className={cn("olympus-lockup flex flex-col items-center", className)}
      ref={ref}
    >
      <div
        aria-hidden="true"
        className="olympus-hero"
        data-testid="olympus-hero"
      >
        <div className="olympus-hero__aurora olympus-in" />
        <Wisps names={["a"]} />
        <Seal id={id} />
        <Wisps names={["b", "c"]} />
      </div>
      <p aria-label="OLYMPUS" className="olympus-wordmark" role="img">
        {[..."OLYMPUS"].map((letter, index) => (
          <span
            className="olympus-in"
            key={letter}
            style={{ animationDelay: `${1000 + index * 60}ms` }}
          >
            {letter}
          </span>
        ))}
      </p>
      <svg
        aria-hidden="true"
        className="olympus-rule olympus-in"
        viewBox="0 0 224 14"
      >
        <path d={OLYMPUS_RULE} fill="none" stroke="#F7C234" strokeWidth="2" />
      </svg>
    </div>
  );
}
