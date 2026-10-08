import type * as React from "react";

import { cn } from "@/shared/lib/cn";
import { isClockTime } from "@/shared/lib/datetime";
import { Input } from "@/shared/ui/input";

export function TimeInput({
  className,
  value,
  ...props
}: Omit<React.ComponentProps<typeof Input>, "type" | "value"> & {
  value: string;
}) {
  return (
    <Input
      aria-invalid={isClockTime(value) ? undefined : true}
      autoComplete="off"
      className={cn(
        "tabular-nums aria-invalid:border-destructive aria-invalid:text-destructive",
        className,
      )}
      inputMode="numeric"
      maxLength={5}
      pattern="([01][0-9]|2[0-3]):[0-5][0-9]"
      placeholder="HH:MM"
      type="text"
      value={value}
      {...props}
    />
  );
}
