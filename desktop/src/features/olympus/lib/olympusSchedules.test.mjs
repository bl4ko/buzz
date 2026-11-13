import assert from "node:assert/strict";
import test from "node:test";

import {
  listOlympusSchedules,
  olympusScheduleMode,
} from "./olympusSchedules.ts";

function schedule(name, extra = {}) {
  return {
    name,
    cron: "*/15 * * * *",
    timeZone: "UTC",
    suspend: false,
    workspace: false,
    asAgent: false,
    prompt: "Go",
    script: null,
    scriptSource: null,
    lastRunTime: null,
    lastResult: null,
    truncated: false,
    gitopsFields: [],
    ...extra,
  };
}

test("lists schedules with next run, suspension, and failures", () => {
  const groups = [
    {
      key: "op:ops",
      name: "ops",
      author: "op",
      workspace: { suspend: false },
      agents: [
        {
          name: "argus",
          author: "op",
          spec: { suspend: false },
          schedules: [
            schedule("a", { lastResult: "Failed" }),
            schedule("b", { suspend: true }),
          ],
        },
        {
          name: "athene",
          author: "op",
          spec: { suspend: true },
          schedules: [schedule("c")],
        },
      ],
    },
  ];
  const rows = listOlympusSchedules(groups, Date.parse("2026-11-13T10:07:00Z"));
  assert.deepEqual(
    rows.map((row) => [
      row.schedule.name,
      row.failed,
      row.suspended,
      row.nextRun?.toISOString() ?? null,
    ]),
    [
      ["a", true, false, "2026-11-13T10:15:00.000Z"],
      ["b", false, true, null],
      ["c", false, true, null],
    ],
  );
});

test("names the schedule mode", () => {
  assert.equal(olympusScheduleMode(schedule("a")), "Prompt");
  assert.equal(
    olympusScheduleMode(
      schedule("a", { prompt: null, script: "x", asAgent: true }),
    ),
    "Script as the agent",
  );
  assert.equal(
    olympusScheduleMode(schedule("a", { script: "x" })),
    "Script, then prompt",
  );
});
