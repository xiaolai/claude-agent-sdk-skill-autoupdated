import { query } from "@anthropic-ai/claude-agent-sdk";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

const CHANGE_REPORT_PATH = process.env.CHANGE_REPORT ?? "/tmp/change-report.json";
const VERIFY_REPORT_PATH = process.env.VERIFY_REPORT ?? "/tmp/verify-report.json";
const SYSTEM_PROMPT_PATH = resolve(__dirname, "mending-prompt.md");
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

const changeReport = readRequired(CHANGE_REPORT_PATH, "change report");
const verifyReport = readRequired(VERIFY_REPORT_PATH, "verify report");
const systemPrompt = readRequired(SYSTEM_PROMPT_PATH, "system prompt");

const parsed = JSON.parse(verifyReport);
const failCount = parsed.checksFailed ?? 0;

if (failCount === 0) {
  console.log("Verify report shows 0 failures. Nothing to mend.");
  process.exit(0);
}

// ---------------------------------------------------------------------------
// Build user message
// ---------------------------------------------------------------------------

const userMessage = `
You are working in the skill directory: ${SKILL_ROOT}

The update agent ran but verification found ${failCount} failure(s).

## Verification Report

\`\`\`json
${verifyReport}
\`\`\`

## Original Change Report

\`\`\`json
${changeReport}
\`\`\`

Fix every failure listed above. Do NOT create git branches or commits.

Today's date is: ${new Date().toISOString().split("T")[0]}
`.trim();

// ---------------------------------------------------------------------------
// Run the mending agent
// ---------------------------------------------------------------------------

console.log(`Mending Agent starting — ${failCount} failure(s) to fix ...`);
console.log(`  Skill root: ${SKILL_ROOT}`);
console.log();

let lastResult: any = null;
let turns = 0;

for await (const message of query({
  prompt: userMessage,
  options: {
    systemPrompt,
    maxTurns: 15,
    maxBudgetUsd: 0.50,
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
  console.log(`Mending agent finished.`);
  console.log(`  Cost: $${lastResult.total_cost_usd?.toFixed(4) ?? "unknown"}`);
  console.log(`  Turns: ${turns}`);
}

// Log cost for daily report
try {
  const costLogPath = "/tmp/agent-costs.json";
  const existing = existsSync(costLogPath)
    ? JSON.parse(readFileSync(costLogPath, "utf-8"))
    : {};
  const mendingRuns = existing.mending ?? [];
  mendingRuns.push({
    costUsd: lastResult?.total_cost_usd ?? 0,
    turns,
  });
  existing.mending = mendingRuns;
  writeFileSync(costLogPath, JSON.stringify(existing, null, 2));
} catch {
  // Non-critical
}

console.log("Mending complete. Re-run verify.sh to check.");
