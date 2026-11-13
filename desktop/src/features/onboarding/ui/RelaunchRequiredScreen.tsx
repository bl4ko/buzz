import { RecoveryScreen } from "./RecoveryScreen";

export function RelaunchRequiredScreen() {
  return (
    <RecoveryScreen
      testId="relaunch-required"
      title="Restart Olympus to finish recovery"
      body="Your identity was updated. Olympus needs to restart so syncing and agents run under it."
    />
  );
}
