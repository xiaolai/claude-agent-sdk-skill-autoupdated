import { query } from "@anthropic-ai/claude-agent-sdk";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));

const SYSTEM_PROMPT_PATH = resolve(__dirname, "research-prompt-py.md");
const STATE_PATH = resolve(__dirname, "state.json");
const SKILL_ROOT = resolve(__dirname, "..");

// Prevent "cannot be launched inside another Claude Code session" error
const cleanEnv = { ...process.env };
delete cleanEnv.CLAUDECODE;

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
const pyState = state.python ?? {};
const researchedIssues = pyState.researchedIssues ?? {};
const alreadyResearched = Object.keys(researchedIssues);

// ---------------------------------------------------------------------------
// Build user message
// ---------------------------------------------------------------------------

const lastAuditedVersion = pyState.lastAuditedVersion ?? "none";

// Read SDK version via importlib.metadata, falling back to state.json
let sdkVersion = pyState.registry?.version ?? "unknown";
try {
  sdkVersion = execSync(
    `python3 -c "import importlib.metadata; print(importlib.metadata.version('claude-agent-sdk'))"`,
    { encoding: "utf-8", timeout: 10_000 },
  ).trim();
} catch {
  // Fall back to state.json version (already set above)
}

// Find the installed package path (source of truth)
let sdkPackagePath = "unknown";
try {
  sdkPackagePath = execSync(
    `python3 -c "import claude_agent_sdk; import os; print(os.path.dirname(claude_agent_sdk.__file__))"`,
    { encoding: "utf-8", timeout: 10_000 },
  ).trim();
} catch {
  // Will be detected by the agent
}

const userMessage = `
You are working in the skill directory: ${SKILL_ROOT}
The state file is at: ${STATE_PATH}
The installed claude_agent_sdk package is at: ${sdkPackagePath}

Current SDK version: ${sdkVersion}
Last audited version: ${lastAuditedVersion}

Already-researched issue numbers (skip these): ${alreadyResearched.length > 0 ? alreadyResearched.join(", ") : "none yet"}

Run Part A (API Surface Audit) first — read types.py and __init__.py from the installed package, then compare against SKILL-python.md and add any missing APIs.
Then run Part B (GitHub Issues Research) — research recent anthropics/claude-agent-sdk-python issues and update Known Issues / rules/claude-agent-sdk-py.md.
Finally run Part C (Final Checks) — verify consistency.

Do NOT create git branches or commits.

Today's date is: ${new Date().toISOString().split("T")[0]}
`.trim();

// ---------------------------------------------------------------------------
// Run the research agent
// ---------------------------------------------------------------------------

console.log("Python Research Agent starting ...");
console.log(`  Skill root: ${SKILL_ROOT}`);
console.log(`  SDK version: ${sdkVersion}`);
console.log(`  SDK package path: ${sdkPackagePath}`);
console.log(`  Last audited: ${lastAuditedVersion}`);
console.log(`  Already researched: ${alreadyResearched.length} issues`);
console.log();

let lastResult: any = null;
let turns = 0;

for await (const message of query({
  prompt: userMessage,
  options: {
    systemPrompt,
    maxTurns: 60,
    maxBudgetUsd: 3.0,
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
    env: cleanEnv,
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
  const updatedPy = updatedState.python ?? {};
  const newResearched = Object.keys(updatedPy.researchedIssues ?? {});
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
  existing.research_py = {
    costUsd: lastResult?.total_cost_usd ?? 0,
    turns,
  };
  writeFileSync(costLogPath, JSON.stringify(existing, null, 2));
} catch {
  // Non-critical
}

console.log("Research complete.");
