import { query } from "@anthropic-ai/claude-agent-sdk";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

const SYSTEM_PROMPT_PATH = resolve(__dirname, "report-prompt.md");
const STATE_PATH = resolve(__dirname, "state.json");
const SKILL_ROOT = resolve(__dirname, "..");
const COST_LOG_PATH = "/tmp/agent-costs.json";

// Prevent "cannot be launched inside another Claude Code session" error
const cleanEnv = { ...process.env };
delete cleanEnv.CLAUDECODE;

// ---------------------------------------------------------------------------
// Load inputs
// ---------------------------------------------------------------------------

function readOptional(path: string): string | null {
  try {
    return readFileSync(path, "utf-8");
  } catch {
    return null;
  }
}

function readRequired(path: string, label: string): string {
  try {
    return readFileSync(path, "utf-8");
  } catch {
    console.error(`ERROR: Could not read ${label} at ${path}`);
    process.exit(2);
  }
}

const systemPrompt = readRequired(SYSTEM_PROMPT_PATH, "system prompt");
const stateJson = readOptional(STATE_PATH) ?? "{}";
const changeReport = readOptional("/tmp/change-report.json");
const verifyReport = readOptional("/tmp/verify-report.json");
const costLog = readOptional(COST_LOG_PATH);
const pipelineLog = readOptional(process.env.PIPELINE_LOG ?? "/tmp/pipeline-log.json");

const today = new Date().toISOString().split("T")[0];

// ---------------------------------------------------------------------------
// Build user message
// ---------------------------------------------------------------------------

let userMessage = `
You are working in the skill directory: ${SKILL_ROOT}
Today's date is: ${today}
Write the report to: ${SKILL_ROOT}/reports/${today}.md

## Available Data

### Pipeline Log (/tmp/pipeline-log.json) — PRIMARY SOURCE
${pipelineLog ? `\`\`\`json\n${pipelineLog}\n\`\`\`` : "Not available — pipeline log was not created."}

### state.json
\`\`\`json
${stateJson}
\`\`\`
`;

if (changeReport) {
  userMessage += `
### Change Report (/tmp/change-report.json)
\`\`\`json
${changeReport}
\`\`\`
`;
} else {
  userMessage += `
### Change Report
No change report found — monitor detected no upstream changes today.
`;
}

if (verifyReport) {
  userMessage += `
### Verify Report (/tmp/verify-report.json)
\`\`\`json
${verifyReport}
\`\`\`
`;
}

if (costLog) {
  userMessage += `
### Agent Costs (/tmp/agent-costs.json)
\`\`\`json
${costLog}
\`\`\`
`;
}

userMessage += `
Please check \`git log --oneline -5\` and \`git diff\` for additional context on what changed today.
Then write the daily report.
`;

userMessage = userMessage.trim();

// ---------------------------------------------------------------------------
// Run the report agent
// ---------------------------------------------------------------------------

console.log("Report Agent starting ...");
console.log(`  Skill root: ${SKILL_ROOT}`);
console.log(`  Report path: reports/${today}.md`);
console.log();

let lastResult: any = null;
let turns = 0;

for await (const message of query({
  prompt: userMessage,
  options: {
    systemPrompt,
    maxTurns: 10,
    maxBudgetUsd: 0.25,
    permissionMode: "bypassPermissions",
    allowDangerouslySkipPermissions: true,
    allowedTools: [
      "Read",
      "Write",
      "Bash",
      "Glob",
      "Grep",
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

let reportCost = 0;
if (lastResult) {
  reportCost = lastResult.total_cost_usd ?? 0;
  console.log();
  console.log("Report agent finished.");
  console.log(`  Cost: $${reportCost.toFixed(4)}`);
  console.log(`  Turns: ${turns}`);
}

// Append own cost to the cost log for record-keeping
try {
  const existing = existsSync(COST_LOG_PATH)
    ? JSON.parse(readFileSync(COST_LOG_PATH, "utf-8"))
    : {};
  existing.report = { costUsd: reportCost, date: today };
  writeFileSync(COST_LOG_PATH, JSON.stringify(existing, null, 2));
} catch {
  // Non-critical
}

// Verify report was written
const reportPath = resolve(SKILL_ROOT, "reports", `${today}.md`);
if (existsSync(reportPath)) {
  console.log(`  Report written: reports/${today}.md`);
} else {
  console.error("  WARNING: Report file was not created.");
}

console.log("Report complete.");
