import assert from "node:assert/strict";
import test from "node:test";

import {
  activeOlympusScheduleFilter,
  applyOlympusScheduleFilter,
  olympusScheduleFilterOptions,
  parseOlympusScheduleFilter,
} from "./olympusScheduleFilter.ts";

function row(workspace, agent, name, failed = false, displayName = null) {
  return {
    key: `${workspace}:${agent}:${name}`,
    workspace,
    failed,
    agent: {
      name: agent,
      spec: { profile: displayName ? { displayName } : null },
    },
    schedule: { name },
  };
}

const ROWS = [
  row("ops", "argus", "daily", true, "Argus"),
  row("ops", "argus", "hourly", false, "Argus"),
  row("ops", "athene", "audit"),
  row("dev", "proof", "ping", true),
];

test("parses a stored filter and ignores bad values", () => {
  assert.deepEqual(parseOlympusScheduleFilter(null), {
    workspace: null,
    agent: null,
    failedOnly: false,
  });
  assert.deepEqual(parseOlympusScheduleFilter("{"), {
    workspace: null,
    agent: null,
    failedOnly: false,
  });
  assert.deepEqual(
    parseOlympusScheduleFilter(
      JSON.stringify({ workspace: "ops", agent: 3, failedOnly: true }),
    ),
    { workspace: "ops", agent: null, failedOnly: true },
  );
});

test("filters by workspace, agent, and failed runs", () => {
  const names = (filter) =>
    applyOlympusScheduleFilter(ROWS, filter).map((item) => item.schedule.name);
  assert.deepEqual(names({ workspace: null, agent: null, failedOnly: false }), [
    "daily",
    "hourly",
    "audit",
    "ping",
  ]);
  assert.deepEqual(
    names({ workspace: "ops", agent: null, failedOnly: false }),
    ["daily", "hourly", "audit"],
  );
  assert.deepEqual(
    names({ workspace: null, agent: "ops/argus", failedOnly: false }),
    ["daily", "hourly"],
  );
  assert.deepEqual(
    names({ workspace: null, agent: "ops/argus", failedOnly: true }),
    ["daily"],
  );
});

test("a stored agent or workspace that is gone does not hide all rows", () => {
  assert.deepEqual(
    activeOlympusScheduleFilter(ROWS, {
      workspace: "gone",
      agent: "gone/zeus",
      failedOnly: true,
    }),
    { workspace: null, agent: null, failedOnly: true },
  );
  assert.deepEqual(
    activeOlympusScheduleFilter(ROWS, {
      workspace: "dev",
      agent: "ops/argus",
      failedOnly: false,
    }),
    { workspace: "dev", agent: null, failedOnly: false },
  );
});

test("agent options use the display name and follow the workspace", () => {
  const all = olympusScheduleFilterOptions(ROWS, null);
  assert.deepEqual(all.workspaces, ["dev", "ops"]);
  assert.deepEqual(all.agents, [
    { value: "ops/argus", label: "Argus · ops" },
    { value: "ops/athene", label: "athene · ops" },
    { value: "dev/proof", label: "proof · dev" },
  ]);
  assert.deepEqual(
    olympusScheduleFilterOptions(ROWS, "ops").agents.map((item) => item.label),
    ["Argus", "athene"],
  );
});
