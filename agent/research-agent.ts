import { query } from "@anthropic-ai/claude-agent-sdk";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

const SYSTEM_PROMPT_PATH = resolve(__dirname, "research-prompt.md");
const STATE_PATH = resolve(__dirname, "state.json");
const SKILL_ROOT = resolve(__dirname, "..");

// ---------------------------------------------------------------------------
// Load inputs
// ---------------------------------------------------------------------------

function readRequired(path: string, label: string): string {
  try {
    return readFileSync(path, "utf-8");
  } catch {
    console.error(`ERROR: Could not read ${label} at ${path}`);
    process.exit(2);
  }
}

const systemPrompt = readRequired(SYSTEM_PROMPT_PATH, "system prompt");
const stateJson = readRequired(STATE_PATH, "state.json");

const state = JSON.parse(stateJson);
const researchedIssues = state.researchedIssues ?? {};
const alreadyResearched = Object.keys(researchedIssues);

// ---------------------------------------------------------------------------
// Build user message
// ---------------------------------------------------------------------------

const userMessage = `
You are working in the skill directory: ${SKILL_ROOT}
The state file is at: ${STATE_PATH}

Already-researched issue numbers (skip these): ${alreadyResearched.length > 0 ? alreadyResearched.join(", ") : "none yet"}

Please research recent GitHub issues from the SDK repo, evaluate them,
and update the skill files and state.json as described in your instructions.

Do NOT create git branches or commits.

Today's date is: ${new Date().toISOString().split("T")[0]}
`.trim();

// ---------------------------------------------------------------------------
// Run the research agent
// ---------------------------------------------------------------------------

console.log("Research Agent starting ...");
console.log(`  Skill root: ${SKILL_ROOT}`);
console.log(`  Already researched: ${alreadyResearched.length} issues`);
console.log();

let lastResult: any = null;
let turns = 0;

for await (const message of query({
  prompt: userMessage,
  options: {
    systemPrompt,
    maxTurns: 40,
    maxBudgetUsd: 2.0,
    permissionMode: "bypassPermissions",
    allowDangerouslySkipPermissions: true,
    allowedTools: [
      "Read",
      "Write",
      "Edit",
      "MultiEdit",
      "Bash",
      "Grep",
      "Glob",
    ],
    settingSources: [],
    cwd: SKILL_ROOT,
  },
})) {
  if (message.type === "assistant") turns++;
  if (message.type === "result") lastResult = message;
}

// ---------------------------------------------------------------------------
// Handle result
// ---------------------------------------------------------------------------

if (lastResult) {
  console.log();
  console.log("Research agent finished.");
  console.log(`  Cost: $${lastResult.total_cost_usd?.toFixed(4) ?? "unknown"}`);
  console.log(`  Turns: ${turns}`);
}

// Check if state.json was updated (research happened)
try {
  const updatedState = JSON.parse(readFileSync(STATE_PATH, "utf-8"));
  const newResearched = Object.keys(updatedState.researchedIssues ?? {});
  const added = newResearched.length - alreadyResearched.length;
  if (added > 0) {
    console.log(`  New issues researched: ${added}`);
  } else {
    console.log("  No new issues to research.");
  }
} catch {
  console.log("  Could not read updated state.");
}

// Log cost for daily report
try {
  const costLogPath = "/tmp/agent-costs.json";
  const existing = existsSync(costLogPath)
    ? JSON.parse(readFileSync(costLogPath, "utf-8"))
    : {};
  existing.research = {
    costUsd: lastResult?.total_cost_usd ?? 0,
    turns,
  };
  writeFileSync(costLogPath, JSON.stringify(existing, null, 2));
} catch {
  // Non-critical
}

console.log("Research complete.");
