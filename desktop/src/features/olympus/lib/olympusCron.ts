type Field = { min: number; max: number; names?: readonly string[] };

const FIELDS: readonly Field[] = [
  { min: 0, max: 59 },
  { min: 0, max: 23 },
  { min: 1, max: 31 },
  {
    min: 1,
    max: 12,
    names: [
      "jan",
      "feb",
      "mar",
      "apr",
      "may",
      "jun",
      "jul",
      "aug",
      "sep",
      "oct",
      "nov",
      "dec",
    ],
  },
  { min: 0, max: 7, names: ["sun", "mon", "tue", "wed", "thu", "fri", "sat"] },
];

const MACROS: Record<string, string> = {
  "@yearly": "0 0 1 1 *",
  "@annually": "0 0 1 1 *",
  "@monthly": "0 0 1 * *",
  "@weekly": "0 0 * * 0",
  "@daily": "0 0 * * *",
  "@midnight": "0 0 * * *",
  "@hourly": "0 * * * *",
};

export type OlympusCron = {
  sets: Set<number>[];
  dayOfMonthAny: boolean;
  dayOfWeekAny: boolean;
};

function value(text: string, field: Field): number | null {
  const index = field.names?.indexOf(text.toLowerCase()) ?? -1;
  const number = index >= 0 ? index + field.min : Number(text);
  return Number.isInteger(number) && number >= field.min && number <= field.max
    ? number
    : null;
}

function parseField(text: string, field: Field): Set<number> | null {
  const set = new Set<number>();
  for (const part of text.split(",")) {
    const [range, stepText] = part.split("/");
    const step = stepText === undefined ? 1 : Number(stepText);
    if (!Number.isInteger(step) || step < 1 || !range) return null;
    let low: number | null;
    let high: number | null;
    if (range === "*" || range === "?") {
      low = field.min;
      high = field.max;
    } else if (range.includes("-")) {
      const [a, b] = range.split("-");
      low = value(a ?? "", field);
      high = value(b ?? "", field);
    } else {
      low = value(range, field);
      high = stepText === undefined ? low : field.max;
    }
    if (low === null || high === null || low > high) return null;
    for (let item = low; item <= high; item += step) set.add(item);
  }
  return set;
}

export function parseOlympusCron(expression: string): OlympusCron | null {
  const trimmed = expression.trim();
  const parts = (MACROS[trimmed] ?? trimmed).split(/\s+/);
  if (parts.length !== 5) return null;
  const sets: Set<number>[] = [];
  for (const [index, part] of parts.entries()) {
    const set = parseField(part, FIELDS[index] as Field);
    if (!set) return null;
    sets.push(set);
  }
  const weekdays = sets[4] as Set<number>;
  if (weekdays.has(7)) weekdays.add(0);
  return {
    sets,
    dayOfMonthAny: parts[2] === "*" || parts[2] === "?",
    dayOfWeekAny: parts[4] === "*" || parts[4] === "?",
  };
}

type Wall = {
  minute: number;
  hour: number;
  day: number;
  month: number;
  weekday: number;
};

const formatters = new Map<string, Intl.DateTimeFormat>();
const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function formatter(timeZone: string) {
  let format = formatters.get(timeZone);
  if (!format) {
    format = new Intl.DateTimeFormat("en-US", {
      timeZone,
      hourCycle: "h23",
      weekday: "short",
      month: "numeric",
      day: "numeric",
      hour: "numeric",
      minute: "numeric",
    });
    formatters.set(timeZone, format);
  }
  return format;
}

function wall(millis: number, timeZone: string): Wall {
  const parts: Record<string, string> = {};
  for (const part of formatter(timeZone).formatToParts(millis)) {
    parts[part.type] = part.value;
  }
  return {
    minute: Number(parts.minute),
    hour: Number(parts.hour) % 24,
    day: Number(parts.day),
    month: Number(parts.month),
    weekday: WEEKDAYS.indexOf(parts.weekday ?? ""),
  };
}

function dayMatches(cron: OlympusCron, time: Wall) {
  const dom = (cron.sets[2] as Set<number>).has(time.day);
  const dow = (cron.sets[4] as Set<number>).has(time.weekday);
  if (cron.dayOfMonthAny || cron.dayOfWeekAny) return dom && dow;
  return dom || dow;
}

const MINUTE = 60_000;

export function nextOlympusRun(
  expression: string | null,
  timeZone: string | null,
  from: number,
): Date | null {
  const cron = expression ? parseOlympusCron(expression) : null;
  if (!cron) return null;
  const zone = timeZone ?? "UTC";
  try {
    formatter(zone);
  } catch {
    return null;
  }
  let time = Math.floor(from / MINUTE) * MINUTE + MINUTE;
  for (let step = 0; step < 20_000; step += 1) {
    const now = wall(time, zone);
    if (
      !(cron.sets[3] as Set<number>).has(now.month) ||
      !dayMatches(cron, now)
    ) {
      time += ((23 - now.hour) * 60 + (60 - now.minute)) * MINUTE;
    } else if (!(cron.sets[1] as Set<number>).has(now.hour)) {
      time += (60 - now.minute) * MINUTE;
    } else if (!(cron.sets[0] as Set<number>).has(now.minute)) {
      time += MINUTE;
    } else {
      return new Date(time);
    }
  }
  return null;
}
