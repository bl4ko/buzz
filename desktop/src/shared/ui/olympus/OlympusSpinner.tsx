import type { CSSProperties } from "react";

import { cn } from "@/shared/lib/cn";
import { OLYMPUS_BOLT } from "./olympusArt";

export function OlympusBoltSpinner({
  className,
  label,
  style,
}: {
  className?: string;
  label?: string;
  style?: CSSProperties;
}) {
  const art = (
    <>
      <span className="olympus-bolt__clip">
        <span className="olympus-bolt__fill" />
      </span>
      <svg
        aria-hidden="true"
        className="olympus-bolt__outline"
        viewBox="590 60 250 510"
      >
        <polygon points={OLYMPUS_BOLT} />
      </svg>
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
    <>
      <span aria-hidden="true" className="olympus-puff" />
      <span aria-hidden="true" className="olympus-puff" />
      <span aria-hidden="true" className="olympus-puff" />
    </>
  );
}
