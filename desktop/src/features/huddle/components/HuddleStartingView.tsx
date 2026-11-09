import { ThemeGrainientBackground } from "@/app/ThemeGrainientBackground";
import { OlympusBoltSpinner } from "@/shared/ui/olympus/OlympusSpinner";

/** Immediate feedback shown while the native huddle session is being prepared. */
export function HuddleStartingView() {
  return (
    <div
      aria-label="Starting huddle"
      className="buzz-setup-loading-shell flex min-h-0 flex-1 items-center justify-center overflow-hidden px-6 text-foreground"
      data-testid="huddle-starting-view"
      role="status"
    >
      <ThemeGrainientBackground />
      <span className="sr-only">Starting huddle</span>
      <OlympusBoltSpinner className="relative z-10 h-16" />
    </div>
  );
}
