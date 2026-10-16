export function shouldReturnToTail(input: {
  wasAtBottom: boolean;
  hasUnseen: boolean;
}) {
  return input.wasAtBottom || input.hasUnseen;
}

export function isTabPanelTarget(target: EventTarget | null) {
  return (
    typeof Element !== "undefined" &&
    target instanceof Element &&
    target.closest("[data-testid='channel-tab-panel']") !== null
  );
}
