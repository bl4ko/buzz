export const STORM_SECTION_COLORS = [
  "#7aa2f7",
  "#73daca",
  "#9ece6a",
  "#bb9af7",
  "#7dcfff",
  "#f7768e",
  "#b4f9f8",
  "#e0af68",
];

export function sectionColorIndex(name: string): number {
  const key = name.trim().toLowerCase();
  let index = 0;
  for (let i = 0; i < key.length; i++) {
    index = (index * 31 + key.charCodeAt(i)) % STORM_SECTION_COLORS.length;
  }
  return index;
}

export function sectionForeground(name: string): string {
  return `var(--sidebar-section-${sectionColorIndex(name)}, currentColor)`;
}
