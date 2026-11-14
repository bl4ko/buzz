import assert from "node:assert/strict";
import test from "node:test";

import { olympusModelChoices } from "./olympusModels.ts";

const workspace = {
  providers: [
    { name: "codex", models: ["gpt-6-luna"], protocols: ["openai"] },
    { name: "claude", models: [], protocols: ["anthropic"] },
  ],
  templates: [{ pool: "claude", model: "claude-sonnet-5-5" }],
};

function agent(pool, model) {
  return { spec: { pool, model }, effectiveSpec: null };
}

const groups = [
  {
    workspace,
    agents: [
      agent("claude", "claude-opus-5-5"),
      agent("codex", "gpt-6-luna"),
      agent("claude", "claude-opus-5-5"),
    ],
  },
];

test("a provider with a model list gives only those models", () => {
  assert.deepEqual(olympusModelChoices(groups, workspace, "codex"), {
    restricted: true,
    models: ["gpt-6-luna"],
  });
});

test("a provider without a list suggests the models in use on that pool", () => {
  assert.deepEqual(olympusModelChoices(groups, workspace, "claude"), {
    restricted: false,
    models: ["claude-opus-5-5", "claude-sonnet-5-5"],
  });
});
