import { query } from "@anthropic-ai/claude-agent-sdk";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

const CHANGE_REPORT_PATH = process.env.CHANGE_REPORT ?? "/tmp/change-report.json";

// Prevent "cannot be launched inside another Claude Code session" error
const cleanEnv = { ...process.env };
delete cleanEnv.CLAUDECODE;
const SYSTEM_PROMPT_PATH = resolve(__dirname, "system-prompt.md");
const SKILL_ROOT = resolve(__dirname, "..");

// ---------------------------------------------------------------------------
// Load inputs
// ---------------------------------------------------------------------------

let changeReport: string;
try {
  changeReport = readFileSync(CHANGE_REPORT_PATH, "utf-8");
} catch {
  console.error(`ERROR: Could not read change report at ${CHANGE_REPORT_PATH}`);
  process.exit(2);
}

let systemPrompt: string;
try {
  systemPrompt = readFileSync(SYSTEM_PROMPT_PATH, "utf-8");
} catch {
  console.error(`ERROR: Could not read system prompt at ${SYSTEM_PROMPT_PATH}`);
  process.exit(2);
}

const parsed = JSON.parse(changeReport);
const newVersion = parsed.newVersion ?? "unknown";

// ---------------------------------------------------------------------------
// Build user message
// ---------------------------------------------------------------------------

const userMessage = `
You are working in the skill directory: ${SKILL_ROOT}

Here is the change report from the monitor:

\`\`\`json
${changeReport}
\`\`\`

Please update all skill files according to your instructions. Do NOT run any git commands.

Today's date is: ${new Date().toISOString().split("T")[0]}
`.trim();

// ---------------------------------------------------------------------------
// Run the agent
// ---------------------------------------------------------------------------

console.log(`SDK Update Agent starting...`);
console.log(`  Skill root: ${SKILL_ROOT}`);
console.log(`  New version: ${newVersion}`);
console.log(`  Change report: ${CHANGE_REPORT_PATH}`);
console.log();

let lastResult: any = null;
let turns = 0;

for await (const message of query({
  prompt: userMessage,
  options: {
    systemPrompt,
    maxTurns: 30,
    maxBudgetUsd: 1.0,
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
  console.log(`Agent finished.`);
  console.log(`  Cost: $${lastResult.total_cost_usd?.toFixed(4) ?? "unknown"}`);
  console.log(`  Turns: ${turns}`);
}

// Log cost for daily report
try {
  const costLogPath = "/tmp/agent-costs.json";
  const existing = existsSync(costLogPath)
    ? JSON.parse(readFileSync(costLogPath, "utf-8"))
    : {};
  existing.update = {
    costUsd: lastResult?.total_cost_usd ?? 0,
    turns,
  };
  writeFileSync(costLogPath, JSON.stringify(existing, null, 2));
} catch {
  // Non-critical
}

console.log("Update agent complete. Run verify.sh to check results.");
