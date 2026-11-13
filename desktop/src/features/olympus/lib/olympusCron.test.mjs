import assert from "node:assert/strict";
import test from "node:test";

import { nextOlympusRun, parseOlympusCron } from "./olympusCron.ts";

const at = (iso) => Date.parse(iso);

test("parses the cron fields of Kubernetes CronJobs", () => {
  assert.ok(parseOlympusCron("*/15 * * * *"));
  assert.ok(parseOlympusCron("41 */4 * * mon-fri"));
  assert.ok(parseOlympusCron("@daily"));
  assert.equal(parseOlympusCron("* * * *"), null);
  assert.equal(parseOlympusCron("61 * * * *"), null);
  assert.equal(parseOlympusCron("5-1 * * * *"), null);
});

test("finds the next run in UTC", () => {
  const next = (cron, from) =>
    nextOlympusRun(cron, "UTC", at(from))?.toISOString() ?? null;
  assert.equal(
    next("*/15 * * * *", "2026-11-13T10:07:30Z"),
    "2026-11-13T10:15:00.000Z",
  );
  assert.equal(
    next("17 * * * *", "2026-11-13T10:17:00Z"),
    "2026-11-13T11:17:00.000Z",
  );
  assert.equal(
    next("0 9 * * 1", "2026-11-13T10:00:00Z"),
    "2026-11-16T09:00:00.000Z",
  );
  assert.equal(
    next("0 0 1 1 *", "2026-11-13T10:00:00Z"),
    "2027-01-01T00:00:00.000Z",
  );
  assert.equal(
    next("0 12 13 * 5", "2026-11-14T13:00:00Z"),
    "2026-11-20T12:00:00.000Z",
  );
});

test("uses the wall clock of the schedule time zone", () => {
  assert.equal(
    nextOlympusRun(
      "10 8 * * *",
      "Europe/Ljubljana",
      at("2026-11-13T06:00:00Z"),
    )?.toISOString(),
    "2026-11-13T07:10:00.000Z",
  );
  assert.equal(
    nextOlympusRun(
      "10 8 * * *",
      "Europe/Ljubljana",
      at("2026-07-13T07:00:00Z"),
    )?.toISOString(),
    "2026-07-14T06:10:00.000Z",
  );
  assert.equal(nextOlympusRun("10 8 * * *", "Mars/Base", Date.now()), null);
  assert.equal(nextOlympusRun(null, "UTC", Date.now()), null);
});
