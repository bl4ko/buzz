import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import test from "node:test";

import { isClockTime } from "./datetime.ts";

const SRC = new URL("../../", import.meta.url);

const TWELVE_HOUR_PATTERNS = [
  /hour12:\s*true/g,
  /\.toLocale(?:Time)?String\(\s*\)/g,
  /type="time"/g,
  /["'](?:AM|PM)["']/g,
];

function sourceFiles() {
  return readdirSync(SRC, { recursive: true })
    .filter((path) => /\.tsx?$/.test(path) && !/\.(?:test|d)\./.test(path))
    .map((path) => [path, readFileSync(new URL(path, SRC), "utf8")]);
}

function lineOf(source, index) {
  return source.slice(0, index).split("\n").length;
}

test("desktop source never shows a 12-hour clock", () => {
  const offenders = [];
  for (const [path, source] of sourceFiles()) {
    for (const pattern of TWELVE_HOUR_PATTERNS) {
      for (const match of source.matchAll(pattern)) {
        offenders.push(`${path}:${lineOf(source, match.index)} ${match[0]}`);
      }
    }
    for (const match of source.matchAll(
      /\b(?:hour: "(?:numeric|2-digit)"|timeStyle:)/g,
    )) {
      const options = source.slice(
        source.lastIndexOf("{", match.index),
        source.indexOf("}", match.index),
      );
      if (!options.includes('hourCycle: "h23"')) {
        offenders.push(`${path}:${lineOf(source, match.index)} ${match[0]}`);
      }
    }
  }
  assert.deepEqual(offenders, []);
});

test("isClockTime accepts only 24-hour HH:MM", () => {
  for (const value of ["00:00", "09:05", "12:30", "23:59"]) {
    assert.ok(isClockTime(value), value);
  }
  for (const value of ["", "9:05", "24:00", "12:60", "2:34 PM", "12:30 AM"]) {
    assert.ok(!isClockTime(value), value);
  }
});
