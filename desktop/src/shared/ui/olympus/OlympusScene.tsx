import {
  type CSSProperties,
  type RefObject,
  useEffect,
  useLayoutEffect,
  useRef,
} from "react";

import { cn } from "@/shared/lib/cn";
import {
  OlympusBolt,
  OlympusCloud,
  OlympusDefs,
  OlympusMountain,
  OlympusRing,
  useOlympusId,
} from "./OlympusMark";
import {
  OLYMPUS_BOLT,
  OLYMPUS_BRANCHES_A,
  OLYMPUS_BRANCHES_B,
  OLYMPUS_CLOUD_BACK,
  OLYMPUS_CLOUD_FRONT,
  OLYMPUS_DISC_RIDGE,
  OLYMPUS_DISC_STARS,
  OLYMPUS_DISC_VIEW_BOX,
  OLYMPUS_MARK_VIEW_BOX,
  OLYMPUS_MEANDER,
  OLYMPUS_MOUNTAIN_SHADE,
  OLYMPUS_PUFF,
  OLYMPUS_PUFF_VIEW_BOX,
  OLYMPUS_RIDGE_FAR,
  OLYMPUS_RIDGE_MID,
  OLYMPUS_RIDGE_NEAR,
  OLYMPUS_RIDGE_VIEW_BOX,
  OLYMPUS_RIM,
  OLYMPUS_RING,
  OLYMPUS_RULE,
  OLYMPUS_SKY_STARS,
  OLYMPUS_SNOW_LIT,
  OLYMPUS_SNOW_SHADE,
  OLYMPUS_WIDE_VIEW_BOX,
} from "./olympusArt";

const STRIKES = [
  ["a", 6400, 9000],
  ["b", 11030, 13000],
] as const;

function useStrikes(ref: RefObject<HTMLElement | null>) {
  useEffect(() => {
    const scene = ref.current;
    if (
      !scene ||
      window.matchMedia("(prefers-reduced-motion: reduce)").matches
    ) {
      return;
    }

    const timers: Record<string, number> = {};
    const schedule = (kind: string, delay: number, period?: number) => {
      timers[kind] = window.setTimeout(() => {
        delete scene.dataset.strike;
        void scene.offsetWidth;
        scene.dataset.strike = kind;
        if (period) schedule(kind, period, period);
      }, delay);
    };
    const start = () => {
      for (const [kind, delay, period] of STRIKES) {
        schedule(kind, delay, period);
      }
    };
    const stop = () => {
      for (const timer of Object.values(timers)) window.clearTimeout(timer);
    };
    const onVisibilityChange = () => {
      stop();
      if (!document.hidden) start();
    };

    schedule("i", 950);
    start();
    document.addEventListener("visibilitychange", onVisibilityChange);
    return () => {
      stop();
      document.removeEventListener("visibilitychange", onVisibilityChange);
    };
  }, [ref]);
}

function twinkle(period: number, phase: number): CSSProperties {
  return { animationDelay: `-${phase}s`, animationDuration: `${period}s` };
}

function Ridge({
  fill,
  flash,
  name,
  points,
}: {
  fill: string;
  flash?: boolean;
  name: string;
  points: string;
}) {
  return (
    <div className={`olympus-ridge olympus-ridge--${name} olympus-in`}>
      <div className={`olympus-drift olympus-drift--${name}`}>
        <svg aria-hidden="true" viewBox={OLYMPUS_RIDGE_VIEW_BOX}>
          <polygon fill={fill} points={`-120,400 ${points} 1720,400`} />
        </svg>
        {flash ? (
          <svg
            aria-hidden="true"
            className="olympus-flash"
            viewBox={OLYMPUS_RIDGE_VIEW_BOX}
          >
            <polyline
              fill="none"
              opacity=".8"
              points={points}
              stroke="#C9D3FF"
              strokeLinejoin="round"
              strokeWidth="3"
            />
          </svg>
        ) : null}
      </div>
    </div>
  );
}

export function OlympusSky() {
  const id = useOlympusId();
  const ref = useRef<HTMLDivElement>(null);
  useStrikes(ref);

  return (
    <div
      aria-hidden="true"
      className="olympus-sky pointer-events-none absolute inset-0 overflow-hidden"
      data-testid="olympus-sky"
      ref={ref}
    >
      <div className="olympus-sky__gradient olympus-in" />
      <div className="olympus-sky__far olympus-in">
        {OLYMPUS_SKY_STARS.map(([x, y, r, period, phase]) => (
          <i
            className="olympus-star"
            key={`${x}-${y}`}
            style={{
              ...twinkle(period, phase),
              height: r * 2,
              left: `${x}%`,
              top: `${y}%`,
              width: r * 2,
            }}
          />
        ))}
        {[1, 2, 3].map((ghost) => (
          <svg
            aria-hidden="true"
            className={`olympus-ghost olympus-ghost--${ghost}`}
            key={ghost}
            viewBox={OLYMPUS_PUFF_VIEW_BOX}
          >
            {ghost === 1 ? <OlympusDefs id={id} /> : null}
            <path d={OLYMPUS_PUFF} fill="#8FA3D9" filter={`url(#${id}-blur)`} />
          </svg>
        ))}
      </div>
      <div className="olympus-ridges">
        <Ridge
          fill={`url(#${id}-rfar)`}
          flash
          name="far"
          points={OLYMPUS_RIDGE_FAR}
        />
        <div className="olympus-fog" />
        <Ridge
          fill={`url(#${id}-rmid)`}
          name="mid"
          points={OLYMPUS_RIDGE_MID}
        />
        <div className="olympus-fog olympus-fog--low" />
        <Ridge
          fill={`url(#${id}-rnear)`}
          name="near"
          points={OLYMPUS_RIDGE_NEAR}
        />
      </div>
      <div className="olympus-sky__flash olympus-flash" />
    </div>
  );
}

function Puff({ id, name }: { id: string; name: string }) {
  return (
    <div className={`olympus-puff olympus-puff--${name}`}>
      <svg aria-hidden="true" viewBox={OLYMPUS_PUFF_VIEW_BOX}>
        <path d={OLYMPUS_PUFF} fill="#FFFFFF" />
        <path
          d={OLYMPUS_PUFF}
          fill={`url(#${id}-puff)`}
          transform="translate(0 6)"
        />
      </svg>
      <svg
        aria-hidden="true"
        className="olympus-flash"
        viewBox={OLYMPUS_PUFF_VIEW_BOX}
      >
        <path d={OLYMPUS_PUFF} fill="#FFF3C8" opacity=".6" />
      </svg>
    </div>
  );
}

function Branches({
  id,
  name,
  sets,
}: {
  id: string;
  name: string;
  sets: string[];
}) {
  return (
    <g className={`olympus-branch olympus-branch--${name}`} fill="none">
      <g
        filter={`url(#${id}-blur)`}
        opacity=".85"
        stroke="#FFC83A"
        strokeWidth="16"
      >
        {sets.map((points) => (
          <polyline key={points} points={points} />
        ))}
      </g>
      {sets.map((points) => (
        <polyline
          className="olympus-branch__core"
          key={points}
          pathLength="1"
          points={points}
          stroke="#FFFDF0"
          strokeWidth="6"
        />
      ))}
    </g>
  );
}

function Medallion({ id }: { id: string }) {
  const glow = `url(#${id}-glow)`;

  return (
    <>
      <svg
        aria-hidden="true"
        className="olympus-hero__wide olympus-hero__halo"
        viewBox={OLYMPUS_WIDE_VIEW_BOX}
      >
        <OlympusDefs id={id} />
        <circle
          {...OLYMPUS_RING}
          fill="none"
          filter={glow}
          stroke="#FFAE1A"
          strokeWidth="68"
        />
      </svg>
      <svg aria-hidden="true" viewBox={OLYMPUS_MARK_VIEW_BOX}>
        <circle {...OLYMPUS_RING} fill={`url(#${id}-disc)`} r="314" />
      </svg>
      {OLYMPUS_DISC_STARS.map(([x, y, r, period, phase]) => (
        <i
          className="olympus-star"
          key={`${x}-${y}`}
          style={{
            ...twinkle(period, phase),
            left: `${(x - r - 92) / 8.4}%`,
            top: `${(y - r - 31) / 8.4}%`,
            width: `${r / 4.2}%`,
          }}
        />
      ))}
      <div className="olympus-hero__disc">
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
        <svg
          aria-hidden="true"
          className="olympus-flash"
          viewBox={OLYMPUS_DISC_VIEW_BOX}
        >
          <polygon
            fill="#FFD27A"
            opacity=".2"
            points={OLYMPUS_MOUNTAIN_SHADE}
          />
          <polygon fill="#FFFFFF" points={OLYMPUS_SNOW_LIT} />
          <polygon fill="#FFF6DC" points={OLYMPUS_SNOW_SHADE} />
          <polyline
            fill="none"
            points={OLYMPUS_RIM}
            stroke="#FFE7A0"
            strokeLinejoin="round"
            strokeWidth="9"
          />
        </svg>
        <div className="olympus-drift olympus-drift--back">
          <svg aria-hidden="true" viewBox={OLYMPUS_DISC_VIEW_BOX}>
            <OlympusCloud back id={id} />
          </svg>
          <svg
            aria-hidden="true"
            className="olympus-flash"
            viewBox={OLYMPUS_DISC_VIEW_BOX}
          >
            <path d={OLYMPUS_CLOUD_BACK} fill="#DCE2FF" opacity=".55" />
          </svg>
        </div>
        <div className="olympus-drift olympus-drift--front">
          <svg aria-hidden="true" viewBox={OLYMPUS_DISC_VIEW_BOX}>
            <OlympusCloud id={id} />
          </svg>
          <svg
            aria-hidden="true"
            className="olympus-flash"
            viewBox={OLYMPUS_DISC_VIEW_BOX}
          >
            <path d={OLYMPUS_CLOUD_FRONT} fill="#FFF3C8" opacity=".7" />
          </svg>
        </div>
      </div>
      <svg aria-hidden="true" viewBox={OLYMPUS_MARK_VIEW_BOX}>
        <OlympusRing id={id} />
      </svg>
      <svg
        aria-hidden="true"
        className="olympus-hero__meander"
        viewBox={OLYMPUS_MARK_VIEW_BOX}
      >
        <path
          d={OLYMPUS_MEANDER}
          fill="none"
          opacity=".82"
          stroke="#7E4505"
          strokeWidth="7"
        />
      </svg>
      <svg
        aria-hidden="true"
        className="olympus-flash"
        viewBox={OLYMPUS_MARK_VIEW_BOX}
      >
        <circle
          {...OLYMPUS_RING}
          fill="none"
          opacity=".44"
          stroke="#FFF8D8"
          strokeWidth="68"
        />
      </svg>
      <svg aria-hidden="true" viewBox={OLYMPUS_MARK_VIEW_BOX}>
        <Branches id={id} name="a" sets={OLYMPUS_BRANCHES_A} />
        <Branches id={id} name="b" sets={OLYMPUS_BRANCHES_B} />
      </svg>
      <div className="olympus-hero__float">
        <div className="olympus-hero__punch">
          <svg
            aria-hidden="true"
            className="olympus-hero__wide olympus-hero__glow"
            viewBox={OLYMPUS_WIDE_VIEW_BOX}
          >
            <polygon fill="#FFB21C" filter={glow} points={OLYMPUS_BOLT} />
          </svg>
          <svg aria-hidden="true" viewBox={OLYMPUS_MARK_VIEW_BOX}>
            <OlympusBolt id={id} />
          </svg>
          <svg
            aria-hidden="true"
            className="olympus-hero__wide olympus-flash"
            viewBox={OLYMPUS_WIDE_VIEW_BOX}
          >
            <polygon
              fill="#FFFFFF"
              filter={glow}
              opacity=".9"
              points={OLYMPUS_BOLT}
            />
            <polygon fill="#FFFFFF" points={OLYMPUS_BOLT} />
          </svg>
        </div>
      </div>
    </>
  );
}

export function OlympusHero({ className }: { className?: string }) {
  const id = useOlympusId();
  const ref = useRef<HTMLDivElement>(null);
  const artRef = useRef<HTMLDivElement>(null);
  useStrikes(ref);

  useLayoutEffect(() => {
    const art = artRef.current;
    if (!art) return;

    const hold = () => {
      art.classList.remove("olympus-in");
      const { height, top } = art.getBoundingClientRect();
      art.style.setProperty(
        "--olympus-rise",
        `${window.innerHeight / 2 - top - height / 2}px`,
      );
      art.classList.add("olympus-in");
    };
    hold();
    // The footer slot takes the help link out of the column after this commit.
    const frame = requestAnimationFrame(hold);
    return () => {
      cancelAnimationFrame(frame);
      art.classList.remove("olympus-in");
    };
  }, []);

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
        <div className="olympus-hero__art" ref={artRef}>
          <Medallion id={id} />
        </div>
        <div className="olympus-hero__puffs olympus-in">
          <Puff id={id} name="a" />
          <Puff id={id} name="b" />
        </div>
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
        <span className="olympus-wordmark__flash olympus-flash" />
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
