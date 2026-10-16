export function tabPanelUnderlay(hasPanel: boolean) {
  return {
    className: hasPanel ? "contents invisible" : "contents",
    inert: hasPanel ? true : undefined,
  };
}
