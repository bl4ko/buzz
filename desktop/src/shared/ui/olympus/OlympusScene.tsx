import { cn } from "@/shared/lib/cn";
import {
  OLYMPUS_BOLT,
  OLYMPUS_COLORS,
  OLYMPUS_MOUNTAIN,
  OLYMPUS_SHADE,
  OLYMPUS_SNOW,
} from "./olympusArt";

function CloudShape() {
  return (
    <>
      <circle cx="-40" cy="0" r="30" />
      <circle cx="0" cy="-16" r="40" />
      <circle cx="42" cy="0" r="28" />
      <rect height="30" rx="15" width="140" x="-70" y="-2" />
    </>
  );
}

function BackCloud({ className }: { className: string }) {
  return (
    <svg
      aria-hidden="true"
      className={cn("olympus-sky__cloud", className)}
      fill={OLYMPUS_COLORS.cloudShadow}
      viewBox="-70 -56 140 84"
    >
      <CloudShape />
    </svg>
  );
}

function FrontCloud({ className }: { className: string }) {
  return (
    <svg
      aria-hidden="true"
      className={cn("olympus-hero__cloud", className)}
      viewBox="-70 -64 140 92"
    >
      <g fill={OLYMPUS_COLORS.cloudShadow}>
        <CloudShape />
      </g>
      <g fill={OLYMPUS_COLORS.marble} transform="translate(0 -8)">
        <CloudShape />
      </g>
    </svg>
  );
}

export function OlympusSky() {
  return (
    <div
      aria-hidden="true"
      className="olympus-sky pointer-events-none absolute inset-0 overflow-hidden"
      data-testid="olympus-sky"
    >
      <BackCloud className="olympus-sky__cloud--a" />
      <BackCloud className="olympus-sky__cloud--b" />
      <span className="olympus-flash olympus-sky__flash" />
    </div>
  );
}

export function OlympusHero({ className }: { className?: string }) {
  return (
    <div className={cn("flex flex-col items-center", className)}>
      <div
        aria-hidden="true"
        className="olympus-hero"
        data-testid="olympus-hero"
      >
        <svg
          aria-hidden="true"
          className="olympus-hero__mountain"
          viewBox="0 40 1024 920"
        >
          <polygon fill={OLYMPUS_COLORS.mountain} points={OLYMPUS_MOUNTAIN} />
          <polygon fill={OLYMPUS_COLORS.mountainShade} points={OLYMPUS_SHADE} />
          <polygon fill={OLYMPUS_COLORS.marble} points={OLYMPUS_SNOW} />
          <polygon
            className="olympus-flash"
            fill="#fff"
            points={OLYMPUS_MOUNTAIN}
          />
        </svg>
        <svg
          aria-hidden="true"
          className="olympus-hero__bolt"
          viewBox="600 70 230 490"
        >
          <polygon fill={OLYMPUS_COLORS.gold} points={OLYMPUS_BOLT} />
        </svg>
        <FrontCloud className="olympus-hero__cloud--a" />
        <FrontCloud className="olympus-hero__cloud--b" />
      </div>
      <p className="olympus-wordmark mt-5 text-4xl">OLYMPUS</p>
    </div>
  );
}
