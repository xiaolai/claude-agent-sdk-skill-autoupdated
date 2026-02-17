# Claude Agent SDK — TypeScript Reference (v0.2.44)

**Package**: `@anthropic-ai/claude-agent-sdk@0.2.44`
**Docs**: https://platform.claude.com/docs/en/agent-sdk/overview
**Repo**: https://github.com/anthropics/claude-agent-sdk-typescript
**Migration**: Renamed from `@anthropic-ai/claude-code`. See [migration guide](https://platform.claude.com/docs/en/agent-sdk/migration-guide).

---

## Table of Contents

- [Breaking Changes](#breaking-changes-v010)
- [Core API](#core-api) — `query()`, `tool()`, `createSdkMcpServer()`
- [Options](#options) — Core, Tools & Permissions, Models & Output, Sessions, MCP & Agents, Advanced
- [Query Object Methods](#query-object-methods)
- [Message Types](#message-types) — All 16 SDKMessage types
- [Hooks](#hooks) — 15 hook events, matchers, return values, async hooks
- [Permissions](#permissions) — 6 modes, `canUseTool` callback
- [MCP Servers](#mcp-servers) — stdio, HTTP, SSE, SDK, claudeai-proxy
- [Subagents](#subagents) — AgentDefinition, tool enforcement workaround
- [Structured Outputs](#structured-outputs)
- [Sandbox](#sandbox)
- [Sessions](#sessions)
- [V2 Session API (Preview)](#v2-session-api-preview) — `unstable_v2_createSession`, `unstable_v2_prompt`
- [Debugging & Error Handling](#debugging--error-handling)
- [Known Issues](#known-issues)
- [Changelog Highlights](#changelog-highlights-v0212--v0239)

---

## Breaking Changes (v0.1.0)

1. **No default system prompt** — SDK uses minimal prompt. Use `systemPrompt: { type: 'preset', preset: 'claude_code' }` for old behavior.
2. **No filesystem settings loaded** — `settingSources` defaults to `[]`. Add `settingSources: ['project']` to load CLAUDE.md.
3. **`ClaudeCodeOptions` renamed** — Now `ClaudeAgentOptions` (Python).

---

## Core API

### `query()`

```typescript
import { query } from "@anthropic-ai/claude-agent-sdk";

function query({
  prompt: string | AsyncIterable<SDKUserMessage>,
  options?: Options
}): Query  // extends AsyncGenerator<SDKMessage, void>
```

**Streaming input**: `prompt` accepts `AsyncIterable<SDKUserMessage>` for real-time, multi-message input:

```typescript
async function* promptStream(): AsyncIterable<SDKUserMessage> {
  yield { type: 'user', content: [{ type: 'text', text: 'First message' }] };
  // yield more messages as they arrive
}

const q = query({ prompt: promptStream() });
for await (const msg of q) { ... }
```

### `tool()`

Creates type-safe MCP tool definitions with Zod schemas.

```typescript
import { tool } from "@anthropic-ai/claude-agent-sdk";

function tool<Schema extends ZodRawShape>(
  name: string,
  description: string,
  inputSchema: Schema,
  handler: (args: z.infer<ZodObject<Schema>>, extra: unknown) => Promise<CallToolResult>,
  _extras?: { annotations?: ToolAnnotations }
): SdkMcpToolDefinition<Schema>
```

Handler returns: `{ content: [{ type: "text", text: "..." }], isError?: boolean }`

### `createSdkMcpServer()`

Creates an in-process MCP server.

```typescript
import { createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";

function createSdkMcpServer(options: {
  name: string;
  version?: string;
  tools?: Array<SdkMcpToolDefinition<any>>;
}): McpSdkServerConfigWithInstance
```

---

## Options

### Core Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `model` | `string` | CLI default | Claude model to use |
| `cwd` | `string` | `process.cwd()` | Working directory |
| `systemPrompt` | `string \| { type: 'preset', preset: 'claude_code', append?: string }` | minimal | System prompt |
| `settingSources` | `SettingSource[]` | `[]` | `'user' \| 'project' \| 'local'` |
| `env` | `Dict<string>` | `process.env` | Environment variables |
| `abortController` | `AbortController` | — | Cancellation controller |

### Tools & Permissions

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `tools` | `string[] \| { type: 'preset', preset: 'claude_code' }` | — | Tool configuration |
| `allowedTools` | `string[]` | All tools | Allowed tool names |
| `disallowedTools` | `string[]` | `[]` | Blocked tool names |
| `permissionMode` | `PermissionMode` | `'default'` | See [Permissions](#permissions) for all 6 modes |
| `canUseTool` | `CanUseTool` | — | Custom permission callback |
| `allowDangerouslySkipPermissions` | `boolean` | `false` | Required with `bypassPermissions` |
| `permissionPromptToolName` | `string` | — | Route permission prompts through a named MCP tool |

### Models & Output

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `outputFormat` | `{ type: 'json_schema', schema: JSONSchema }` | — | Structured output schema |
| `thinking` | `ThinkingConfig` | — | `{ type: 'enabled', budgetTokens: number } \| { type: 'disabled' } \| { type: 'adaptive' }` |
| `effort` | `'low' \| 'medium' \| 'high' \| 'max'` | — | Controls response effort level |
| `maxThinkingTokens` | `number` | — | **Deprecated** — use `thinking` instead |
| `fallbackModel` | `string` | — | Fallback model on failure |
| `betas` | `SdkBeta[]` | `[]` | Beta features (e.g., `['context-1m-2025-08-07']`) |
| `includePartialMessages` | `boolean` | `false` | Include streaming partial messages |

### Sessions

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `resume` | `string` | — | Session ID to resume |
| `forkSession` | `boolean` | `false` | Fork when resuming |
| `continue` | `boolean` | `false` | Continue most recent conversation |
| `sessionId` | `string` | auto | Custom UUID for session (v0.2.33) |
| `resumeSessionAt` | `string` | — | Resume at specific message UUID |
| `persistSession` | `boolean` | `true` | When false, disables session persistence to disk |
| `maxTurns` | `number` | — | Max conversation turns (critical safety net — sessions never timeout) |
| `maxBudgetUsd` | `number` | — | Max budget in USD |
| `enableFileCheckpointing` | `boolean` | `false` | Enable file rollback |

### MCP & Agents

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `mcpServers` | `Record<string, McpServerConfig>` | `{}` | MCP server configs |
| `agents` | `Record<string, AgentDefinition>` | — | Subagent definitions |
| `agent` | `string` | — | Apply a named agent's config to main thread (like `--agent` CLI flag) |
| `plugins` | `SdkPluginConfig[]` | `[]` | `{ type: 'local', path: string }` |
| `strictMcpConfig` | `boolean` | `false` | Strict MCP validation |

### Advanced

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `sandbox` | `SandboxSettings` | — | Sandbox configuration |
| `hooks` | `Partial<Record<HookEvent, HookCallbackMatcher[]>>` | `{}` | Hook callbacks |
| `additionalDirectories` | `string[]` | `[]` | Extra directories for Claude to access |
| `debug` | `boolean` | — | Enable debug logging (v0.2.30) |
| `debugFile` | `string` | — | Debug log file path (v0.2.30) |
| `stderr` | `(data: string) => void` | — | stderr callback |
| `executable` | `'bun' \| 'deno' \| 'node'` | auto | JS runtime |
| `executableArgs` | `string[]` | — | Additional arguments for the JS runtime |
| `extraArgs` | `Record<string, string \| null>` | — | Additional CLI arguments to pass to Claude Code |
| `pathToClaudeCodeExecutable` | `string` | auto | Explicit path to Claude Code CLI binary |
| `spawnClaudeCodeProcess` | `(options: SpawnOptions) => SpawnedProcess` | — | Custom spawn function for VMs/containers/remote execution |

---

## Query Object Methods

```typescript
const q = query({ prompt: "..." });

for await (const message of q) { ... }    // Primary: iterate messages

// Control
await q.interrupt();                        // Interrupt (streaming input mode)
q.close();                                  // Force terminate (v0.2.15)
await q.setModel("claude-opus-4-6");        // Change model
await q.setPermissionMode("acceptEdits");   // Change permissions
await q.setMaxThinkingTokens(4096);         // Change thinking budget (number | null)
await q.streamInput(stream);                // Stream user messages (AsyncIterable<SDKUserMessage>)
await q.stopTask(taskId);                   // Stop a running background task by ID

// Introspection
await q.supportedModels();                  // List available models
await q.supportedCommands();                // List slash commands
await q.mcpServerStatus();                  // MCP server status
await q.accountInfo();                      // Account info
await q.initializationResult();             // Full init response (commands, models, account, styles)

// MCP management
await q.reconnectMcpServer("server-name");  // Reconnect MCP server (v0.2.21)
await q.toggleMcpServer("server-name", enabled); // Toggle MCP server (v0.2.21)
await q.setMcpServers(newServersConfig);    // Replace MCP servers mid-session

// File checkpointing (requires enableFileCheckpointing: true)
await q.rewindFiles(userMessageUuid, { dryRun?: boolean }); // Rewind to checkpoint
```

### Initialization Result Type

The `initializationResult()` method returns detailed session initialization data:

```typescript
type SDKControlInitializeResponse = {
  commands: SlashCommand[];              // Available skills/slash commands
  output_style: string;                  // Current output style setting
  available_output_styles: string[];     // All available output style options
  models: ModelInfo[];                   // Available models
  account: AccountInfo;                  // User account information
};

type SlashCommand = {
  name: string;           // Command name (without leading slash)
  description: string;    // What the command does
  argumentHint: string;   // Hint for arguments (e.g., "<file>")
};

type ModelInfo = {
  value: string;          // Model identifier for API calls
  displayName: string;    // Human-readable name
  description: string;    // Model capabilities description
};

type AccountInfo = {
  email?: string;
  organization?: string;
  subscriptionType?: string;
  tokenSource?: string;
  apiKeySource?: string;
};
```

---

## Message Types

The SDK emits 16 message types through the async generator:

```typescript
type SDKMessage =
  // Core messages
  | SDKAssistantMessage           // type: 'assistant' — agent responses
  | SDKUserMessage                // type: 'user' — user input
  | SDKUserMessageReplay          // type: 'user', isReplay: true — replayed messages on resume
  | SDKResultMessage              // type: 'result' — final result
  | SDKSystemMessage              // type: 'system', subtype: 'init' — session init
  | SDKPartialAssistantMessage    // type: 'stream_event' (includePartialMessages)
  | SDKCompactBoundaryMessage     // type: 'system', subtype: 'compact_boundary'
  // Status & progress
  | SDKStatusMessage              // type: 'system', subtype: 'status' — status updates (e.g., 'compacting')
  | SDKToolProgressMessage        // type: 'tool_progress' — tool execution progress with elapsed time
  | SDKToolUseSummaryMessage      // type: 'tool_use_summary' — summary of tool usage
  | SDKAuthStatusMessage          // type: 'auth_status' — authentication status
  // Hook messages
  | SDKHookStartedMessage         // type: 'system', subtype: 'hook_started'
  | SDKHookProgressMessage        // type: 'system', subtype: 'hook_progress' — hook stdout/stderr
  | SDKHookResponseMessage        // type: 'system', subtype: 'hook_response' — hook outcome
  // Task & persistence
  | SDKTaskNotificationMessage    // type: 'system', subtype: 'task_notification' — background task events
  | SDKFilesPersistedEvent        // type: 'system', subtype: 'files_persisted'
```

### SDKResultMessage

```typescript
// Success
{ type: 'result', subtype: 'success', session_id, duration_ms, duration_api_ms,
  is_error: false, num_turns, result: string, total_cost_usd,
  usage, modelUsage, permission_denials, structured_output?, stop_reason? }

// Error variants
{ type: 'result', subtype: 'error_max_turns' | 'error_during_execution'
  | 'error_max_budget_usd' | 'error_max_structured_output_retries',
  session_id, is_error: true, errors: string[], ... }

// Error codes (SDKAssistantMessageError)
'authentication_failed' | 'billing_error' | 'rate_limit' |
'invalid_request' | 'server_error' | 'unknown' | 'max_output_tokens'
```

### SDKSystemMessage (init)

```typescript
{ type: 'system', subtype: 'init', session_id, model, tools: string[],
  cwd, mcp_servers: { name, status }[], permissionMode, slash_commands,
  apiKeySource, output_style,
  agents?: string[],              // Available agent names
  betas?: string[],               // Active beta features
  claude_code_version: string,    // CLI version (e.g., "2.1.41")
  skills: string[],               // Loaded skills
  plugins: { name: string; path: string }[]  // Active plugins
}
```

### SDKAssistantMessage

```typescript
{ type: 'assistant', uuid, session_id, message: APIAssistantMessage,
  parent_tool_use_id: string | null }
```

### SDKUserMessageReplay

```typescript
// Replayed user messages on session resume
{ type: 'user', ..., isReplay: true }
```

### Streaming Pattern

```typescript
let sessionId: string;
for await (const message of query({ prompt: "...", options })) {
  switch (message.type) {
    case 'system':
      if (message.subtype === 'init') sessionId = message.session_id;
      if (message.subtype === 'status') console.log('Status:', message.status);
      if (message.subtype === 'hook_progress') console.log('Hook:', message.data);
      if (message.subtype === 'task_notification') console.log('Task:', message.task_id);
      break;
    case 'assistant':
      console.log(message.message);
      break;
    case 'tool_progress':
      console.log(`Tool running: ${message.tool_name} (${message.elapsed_ms}ms)`);
      break;
    case 'result':
      if (message.subtype === 'success') {
        console.log(message.result);
        if (message.structured_output) console.log(message.structured_output);
      } else {
        console.error(message.errors);
      }
      break;
  }
}
```

---

## Hooks

Hooks use **callback matchers**: an optional regex `matcher` for tool names and an array of `hooks` callbacks.

### Hook Events

| Event | Fires When | TS | Py |
|-------|-----------|----|----|
| `Setup` | On init or maintenance trigger | Yes | No |
| `PreToolUse` | Before tool execution | Yes | Yes |
| `PostToolUse` | After tool execution | Yes | Yes |
| `PostToolUseFailure` | Tool execution failed | Yes | No |
| `UserPromptSubmit` | User prompt received | Yes | Yes |
| `Stop` | Agent stopping | Yes | Yes |
| `SubagentStart` | Subagent spawned | Yes | No |
| `SubagentStop` | Subagent completed | Yes | Yes |
| `PreCompact` | Before context compaction | Yes | Yes |
| `PermissionRequest` | Permission dialog would show | Yes | No |
| `SessionStart` | Session begins | Yes | No |
| `SessionEnd` | Session ends | Yes | No |
| `Notification` | Agent status message | Yes | No |
| `TeammateIdle` | Teammate agent is idle (v0.2.33) | Yes | No |
| `TaskCompleted` | Background task completed (v0.2.33) | Yes | No |

### Hook Callback Signature

```typescript
type HookCallback = (
  input: HookInput,              // Event-specific data
  toolUseID: string | undefined, // Correlate Pre/PostToolUse
  options: { signal: AbortSignal }
) => Promise<HookJSONOutput>;
```

### Hook Configuration

```typescript
const response = query({
  prompt: "...",
  options: {
    hooks: {
      Setup: [{ hooks: [initCallback] }],  // fires on init/maintenance
      PreToolUse: [
        { matcher: 'Write|Edit', hooks: [protectFiles] },
        { matcher: '^mcp__', hooks: [logMcpCalls] },
        { hooks: [globalLogger] }  // no matcher = all tools
      ],
      Stop: [{ hooks: [cleanup] }],  // matchers ignored for lifecycle hooks
      Notification: [{ hooks: [notifySlack] }],
      TeammateIdle: [{ hooks: [coordinateTeam] }],
      TaskCompleted: [{ hooks: [onTaskDone] }]
    }
  }
});
```

### Hook Return Values

```typescript
// Allow (empty = allow)
return {};

// Block a tool (PreToolUse only)
// WARNING: permissionDecision: 'deny' causes API 400 error — see Known Issue #12
return {
  hookSpecificOutput: {
    hookEventName: input.hook_event_name,
    permissionDecision: 'allow',  // Use 'allow' with modified input instead of 'deny'
    updatedInput: { command: `echo "BLOCKED: ${reason}"` }
  }
};

// Modify tool input (PreToolUse only, requires permissionDecision: 'allow')
return {
  hookSpecificOutput: {
    hookEventName: input.hook_event_name,
    permissionDecision: 'allow',
    updatedInput: { ...input.tool_input, file_path: `/sandbox${path}` }
  }
};

// Modify MCP tool output (PostToolUse only)
return {
  hookSpecificOutput: {
    hookEventName: input.hook_event_name,
    updatedMCPToolOutput: { content: [{ type: 'text', text: 'filtered output' }] }
  }
};

// Inject context (PreToolUse, PostToolUse, UserPromptSubmit, SessionStart)
return {
  hookSpecificOutput: {
    hookEventName: input.hook_event_name,
    additionalContext: 'Extra instructions for Claude'
  }
};

// Decision-based response
return { decision: 'approve', reason: 'Looks safe' };   // or 'block'

// Stop agent
return { continue: false, stopReason: 'Budget exceeded' };

// Inject system message
return { systemMessage: 'Remember: /etc is protected' };

// Suppress hook output
return { suppressOutput: true };
```

### Async Hooks

Hooks can run asynchronously with a timeout:

```typescript
return { async: true, asyncTimeout: 30000 };  // 30s timeout
```

### Hook Input Fields

Common fields on all hooks: `session_id`, `transcript_path`, `cwd`, `permission_mode`

| Field | Hooks |
|-------|-------|
| `tool_name`, `tool_input`, `tool_use_id` | PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest |
| `tool_response` | PostToolUse |
| `error`, `is_interrupt` | PostToolUseFailure |
| `prompt` | UserPromptSubmit |
| `stop_hook_active` | Stop, SubagentStop |
| `agent_id`, `agent_type` | SubagentStart |
| `agent_id`, `agent_type`, `agent_transcript_path` | SubagentStop |
| `trigger` (`'init' \| 'maintenance'`) | Setup |
| `custom_instructions` | Setup |
| `trigger`, `custom_instructions` | PreCompact |
| `source` | SessionStart (`'startup' \| 'resume' \| 'clear' \| 'compact'`) |
| `agent_type`, `model` | SessionStart |
| `reason` | SessionEnd |
| `message`, `title`, `notification_type` | Notification |
| `permission_suggestions` | PermissionRequest |
| `teammate_name`, `team_name` | TeammateIdle |
| `task_id`, `task_subject`, `task_description`, `teammate_name`, `team_name` | TaskCompleted |

---

## Permissions

### PermissionMode

```typescript
type PermissionMode =
  | 'default'            // Prompt user for each action
  | 'acceptEdits'        // Auto-allow file edits, prompt for others
  | 'bypassPermissions'  // Skip all prompts (requires allowDangerouslySkipPermissions)
  | 'plan'               // Read-only planning mode — no writes/execution
  | 'delegate'           // Delegate permission decisions to a handler
  | 'dontAsk';           // Don't prompt — deny if not pre-approved
```

**Note**: `allowedTools` is ignored when `permissionMode: 'bypassPermissions'` — Claude can use any tool.

### canUseTool

```typescript
type CanUseTool = (
  toolName: string,
  input: Record<string, unknown>,
  options: {
    signal: AbortSignal;
    suggestions?: PermissionUpdate[];  // Permission suggestions from Claude
    blockedPath?: string;              // Path that triggered a permission check
    decisionReason?: string;           // Why this permission check was triggered
    toolUseID: string;                 // ID of the tool use block
    agentID?: string;                  // Subagent ID (if called from a subagent)
  }
) => Promise<PermissionResult>;

type PermissionResult =
  | { behavior: 'allow'; updatedInput?: Record<string, unknown>; updatedPermissions?: PermissionUpdate[]; toolUseID?: string; }
  | { behavior: 'deny'; message: string; interrupt?: boolean; toolUseID?: string; };
```

Example:

```typescript
canUseTool: async (toolName, input, { signal, toolUseID, agentID }) => {
  if (['Read', 'Grep', 'Glob'].includes(toolName)) {
    return { behavior: 'allow', updatedInput: input };
  }
  if (toolName === 'Bash' && /rm -rf|dd if=|mkfs/.test(String(input.command ?? ''))) {
    return { behavior: 'deny', message: 'Destructive command blocked' };
  }
  return { behavior: 'allow', updatedInput: input };
}
```

---

## MCP Servers

### Config Types

```typescript
// stdio (type field optional, defaults to 'stdio')
{ command: "npx", args: ["@playwright/mcp@latest"], env?: Record<string, string> }

// HTTP (type required)
{ type: "http", url: "https://api.example.com/mcp", headers?: Record<string, string> }

// SSE (type required)
{ type: "sse", url: "https://api.example.com/mcp/sse", headers?: Record<string, string> }

// In-process SDK server
{ type: "sdk", name: "my-server", instance: mcpServerInstance }

// Claude AI Proxy (routes through Claude.ai)
{ type: "claudeai-proxy", url: "https://...", id: "server-id" }
```

**Tool naming**: `mcp__<server-name>__<tool-name>` (double underscores)

### In-Process MCP Server Example

```typescript
import { query, tool, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";

const weatherTool = tool("get_weather", "Get weather for a city", {
  city: z.string().describe("City name")
}, async (args) => ({
  content: [{ type: "text", text: `Weather in ${args.city}: 72°F, sunny` }]
}));

const server = createSdkMcpServer({ name: "weather", tools: [weatherTool] });

for await (const msg of query({
  prompt: "What's the weather in Tokyo?",
  options: { mcpServers: { weather: server } }
})) {
  if (msg.type === 'result' && msg.subtype === 'success') console.log(msg.result);
}
```

### MCP Tool Annotations (v0.2.27)

```typescript
const myTool = tool("delete_record", "Delete a record", {
  id: z.string()
}, async (args) => { ... });
myTool.annotations = { destructiveHint: true, readOnlyHint: false };
```

### MCP Gotchas

- **URL-based servers require `type` field** — missing it causes opaque "exit code 1" (see [Known Issue #3](#3-mcp-config-missing-type-field))
- **SDK MCP servers don't support concurrent queries** — use stdio servers instead (see [Known Issue #7](#7-sdk-mcp-servers-fail-from-concurrent-query-calls))
- **In-process MCP servers don't work in subagents** since v0.2.23 ([#158](https://github.com/anthropics/claude-agent-sdk-typescript/issues/158))
- **HTTP MCP servers fail behind corporate proxies** — use SSE or stdio instead ([Known Issue #14](#14-http-mcp-servers-fail-behind-corporate-proxies))
- **Unicode U+2028/U+2029 in tool results breaks JSON** — sanitize all MCP responses (see [Known Issue #5](#5-unicode-line-separators-break-json))
- **5-minute hard timeout** on MCP tool calls — no workaround (see [Known Issue #10](#10-mcp-tool-calls-timeout-at-5-minutes-despite-mcp_tool_timeout))

---

## Subagents

### AgentDefinition

```typescript
type AgentDefinition = {
  description: string;        // When to use (used by main agent for delegation)
  prompt: string;             // System prompt
  tools?: string[];           // Allowed tools (inherits if omitted) — NOT enforced, see warning
  disallowedTools?: string[]; // Tools to block — NOT enforced, see warning
  model?: 'sonnet' | 'opus' | 'haiku' | 'inherit';
  mcpServers?: AgentMcpServerSpec[];  // Per-agent MCP servers
  skills?: string[];          // Skill names to preload
  maxTurns?: number;          // Max turns for this subagent
  criticalSystemReminder_EXPERIMENTAL?: string;  // Critical reminder added to system prompt
}
```

Include `Task` in parent's `allowedTools` — subagents are invoked via the Task tool.

```typescript
for await (const msg of query({
  prompt: "Use the reviewer to check this code",
  options: {
    allowedTools: ["Read", "Glob", "Grep", "Task"],
    agents: {
      "reviewer": {
        description: "Code review specialist",
        prompt: "Review code for bugs and best practices.",
        tools: ["Read", "Glob", "Grep"],
        model: "haiku",
        maxTurns: 10
      }
    }
  }
})) { ... }
```

### Tool Enforcement Warning

**`AgentDefinition.tools` and `disallowedTools` are NOT enforced at the API level** ([#172](https://github.com/anthropics/claude-agent-sdk-typescript/issues/172), [#163](https://github.com/anthropics/claude-agent-sdk-typescript/issues/163)). Subagents can call tools they shouldn't have access to, potentially causing infinite recursion.

Workaround — use `canUseTool` with session tracking:

```typescript
const activeSubagentSessions = new Map<string, string>();

const options = {
  hooks: {
    SubagentStart: [{ hooks: [async (input) => {
      activeSubagentSessions.set(input.session_id, input.agent_name);
      return {};
    }] }],
    SubagentStop: [{ hooks: [async (input) => {
      activeSubagentSessions.delete(input.session_id);
      return {};
    }] }]
  },
  canUseTool: async (toolName, input, { signal }) => {
    const sessionId = input.session_id;
    if (toolName === "Task" && activeSubagentSessions.has(sessionId)) {
      return { behavior: 'deny', message: 'Task tool blocked in subagents' };
    }
    return { behavior: 'allow', updatedInput: input };
  }
};
```

### Subagent Cleanup Warning

Subagents don't auto-stop when the parent stops ([#132](https://github.com/anthropics/claude-agent-sdk-typescript/issues/132), [#142](https://github.com/anthropics/claude-agent-sdk-typescript/issues/142)). This causes orphan processes and potential OOM.

Workaround — use a Stop hook:

```typescript
hooks: {
  Stop: [{ hooks: [async () => {
    console.log("Cleaning up subagents");
    // Track and terminate spawned processes
    return {};
  }] }]
}
```

---

## Structured Outputs

Define a JSON Schema and get validated data in `message.structured_output`.

```typescript
import { query } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";

const schema = z.object({
  summary: z.string(),
  sentiment: z.enum(['positive', 'neutral', 'negative']),
  confidence: z.number()
});

for await (const msg of query({
  prompt: "Analyze this feedback",
  options: {
    outputFormat: {
      type: "json_schema",
      schema: z.toJSONSchema(schema)  // Zod v3.24.1+ or v4+
    }
  }
})) {
  if (msg.type === 'result' && msg.subtype === 'success' && msg.structured_output) {
    const parsed = schema.safeParse(msg.structured_output);
    if (parsed.success) console.log(parsed.data);
  }
}
```

Error subtype `error_max_structured_output_retries` indicates validation failures after retries.

---

## Sandbox

```typescript
type SandboxSettings = {
  enabled?: boolean;
  autoAllowBashIfSandboxed?: boolean;
  excludedCommands?: string[];          // Always bypass sandbox
  allowUnsandboxedCommands?: boolean;   // Let model request unsandboxed execution
  network?: {
    allowLocalBinding?: boolean;
    allowUnixSockets?: string[];
    allowAllUnixSockets?: boolean;
    httpProxyPort?: number;
    socksProxyPort?: number;
    allowedDomains?: string[];          // Restrict network to specific domains
    allowManagedDomainsOnly?: boolean;  // Only allow managed domains
  };
  ignoreViolations?: Record<string, string[]>;  // Generic violation categories
  enableWeakerNestedSandbox?: boolean;
  ripgrep?: { command: string; args?: string[] };  // Custom ripgrep binary
};
```

`excludedCommands` = static allowlist (model has no control).
`allowUnsandboxedCommands` = model can set `dangerouslyDisableSandbox: true` in Bash input, which falls back to `canUseTool` for approval.

---

## Sessions

```typescript
// Capture session ID
let sessionId: string;
for await (const msg of query({ prompt: "Read auth module" })) {
  if (msg.type === 'system' && msg.subtype === 'init') sessionId = msg.session_id;
}

// Resume
for await (const msg of query({
  prompt: "Now find callers",
  options: { resume: sessionId }
})) { ... }

// Fork (creates new branch, original unchanged)
for await (const msg of query({
  prompt: "Try GraphQL instead",
  options: { resume: sessionId, forkSession: true }
})) { ... }

// Disable persistence (ephemeral sessions)
for await (const msg of query({
  prompt: "Quick analysis",
  options: { persistSession: false }
})) { ... }
```

**Session tips:**
- Use `maxTurns` as a safety net — sessions never timeout on their own
- Use `maxBudgetUsd` to limit costs per session
- Fork proactively before context gets too large ([Known Issue #2](#2-context-length-exceeded-session-breaking))
- `persistSession: false` disables writing session state to disk

---

## V2 Session API (Preview)

The V2 API simplifies multi-turn conversations by removing async generators. **Unstable** — APIs may change.

```typescript
import {
  unstable_v2_createSession,
  unstable_v2_resumeSession,
  unstable_v2_prompt
} from "@anthropic-ai/claude-agent-sdk";
```

### Create Session

```typescript
// Using 'await using' for automatic cleanup (TC39 Explicit Resource Management)
await using session = unstable_v2_createSession({
  model: 'claude-sonnet-4-5-20250929',
  permissionMode: 'bypassPermissions',
  allowDangerouslySkipPermissions: true
});

// Send a message
await session.send("Analyze this codebase");

// Stream responses
for await (const msg of session.stream()) {
  if (msg.type === 'result') console.log(msg.result);
}

// Multi-turn: send another message on the same session
await session.send("Now refactor the auth module");
for await (const msg of session.stream()) { ... }

// Session ID available for later resumption
console.log(session.sessionId);
```

### Resume Session

```typescript
await using session = unstable_v2_resumeSession(savedSessionId, {
  model: 'claude-sonnet-4-5-20250929'
});
await session.send("Continue where we left off");
for await (const msg of session.stream()) { ... }
```

### One-Shot Convenience

```typescript
const result = await unstable_v2_prompt("Explain this error", {
  model: 'claude-haiku-4-5-20251001'
});
console.log(result.result);
```

### SDKSession Interface

```typescript
interface SDKSession {
  readonly sessionId: string;
  send(message: string | SDKUserMessage): Promise<void>;
  stream(): AsyncGenerator<SDKMessage, void>;
  close(): void;
  [Symbol.asyncDispose](): Promise<void>;  // supports 'await using'
}
```

### V2 Limitations

`SDKSessionOptions` is a subset of `Options`. The V2 API does **NOT** support:
- `cwd` ([#176](https://github.com/anthropics/claude-agent-sdk-typescript/issues/176))
- `settingSources` ([#176](https://github.com/anthropics/claude-agent-sdk-typescript/issues/176))
- `plugins` ([#171](https://github.com/anthropics/claude-agent-sdk-typescript/issues/171))
- `systemPrompt` ([#160](https://github.com/anthropics/claude-agent-sdk-typescript/issues/160))
- `mcpServers` ([#154](https://github.com/anthropics/claude-agent-sdk-typescript/issues/154))
- `agents`, `outputFormat`, `sandbox`
- File checkpointing ([#133](https://github.com/anthropics/claude-agent-sdk-typescript/issues/133))

Use the standard `query()` API if you need these features.

---

## Debugging & Error Handling

### Debug Options

```typescript
// Enable debug logging
const q = query({
  prompt: "...",
  options: {
    debug: true,                    // Logs to stderr
    debugFile: '/tmp/agent.log'     // Also logs to file
  }
});
```

**Warning**: Do NOT use `ANTHROPIC_LOG=debug` — it corrupts the SDK JSON protocol ([Known Issue #15](#15-anthropic_logdebug-corrupts-sdk-protocol)). Use `debug: true` instead.

### Diagnostic Checklist for "process exited with code 1"

This opaque error ([#106](https://github.com/anthropics/claude-agent-sdk-typescript/issues/106)) has many causes:

1. **Missing `type` field on URL-based MCP config** — add `type: "http"` or `type: "sse"`
2. **Invalid model ID** — verify model string (e.g., `claude-sonnet-4-5-20250929`, not `claude-3.5-sonnet`)
3. **CLI not installed** — run `npm install -g @anthropic-ai/claude-code`
4. **`ANTHROPIC_LOG=debug` set** — unset it, use `debug: true` instead
5. **Bundled with esbuild/bun** — set `pathToClaudeCodeExecutable` explicitly
6. **`OTEL_*_EXPORTER=none`** — remove or change OpenTelemetry env vars ([#136](https://github.com/anthropics/claude-agent-sdk-typescript/issues/136))
7. **Enable debug mode** — add `debug: true` to see actual error

### Error Result Types

```typescript
// Check result subtypes for specific failures
switch (message.subtype) {
  case 'success':               // Normal completion
  case 'error_max_turns':       // Hit maxTurns limit
  case 'error_max_budget_usd':  // Hit maxBudgetUsd limit
  case 'error_during_execution': // Runtime error
  case 'error_max_structured_output_retries': // Schema validation failed
}
```

### Cost Monitoring

```typescript
for await (const msg of query({ prompt: "...", options: { maxBudgetUsd: 5.00 } })) {
  if (msg.type === 'result' && msg.subtype === 'success') {
    console.log(`Cost: $${msg.total_cost_usd}`);
    console.log(`Turns: ${msg.num_turns}`);
    // Per-model token usage
    for (const [model, usage] of Object.entries(msg.modelUsage ?? {})) {
      console.log(`  ${model}: ${usage.input_tokens}in / ${usage.output_tokens}out`);
    }
  }
}
```

---

## Known Issues

### #1: CLI Not Found
**Error**: `CLI_NOT_FOUND`
**Fix**: `npm install -g @anthropic-ai/claude-code`

### #2: Context Length Exceeded (Session-Breaking)
**Error**: "Prompt is too long" ([#138](https://github.com/anthropics/claude-agent-sdk-typescript/issues/138))
**Behavior**: Session permanently broken — cannot recover or compact.
**Prevention**: Monitor session age, fork proactively, use `maxTurns` / `maxBudgetUsd`.

### #3: MCP Config Missing `type` Field
**Error**: Cryptic "process exited with code 1" ([#131](https://github.com/anthropics/claude-agent-sdk-typescript/issues/131))
**Fix**: URL-based MCP servers require `type: "http"` or `type: "sse"`.

### #4: Orphan Subagents
Subagents don't stop when parent stops ([#132](https://github.com/anthropics/claude-agent-sdk-typescript/issues/132), [#142](https://github.com/anthropics/claude-agent-sdk-typescript/issues/142)).
**Fix**: Implement Stop hook cleanup (see Subagents section).

### #5: Unicode Line Separators Break JSON
U+2028/U+2029 in MCP tool results break parsing ([#137](https://github.com/anthropics/claude-agent-sdk-typescript/issues/137), [MCP Python SDK #1356](https://github.com/modelcontextprotocol/python-sdk/issues/1356)).
**Fix**: Sanitize: `content.replace(/[\u2028\u2029]/g, ' ')`

### #6: ANTHROPIC_BASE_URL via env option broken in v0.2.8+
**Error**: `error_during_execution` with 0 tokens when using custom base URL ([#144](https://github.com/anthropics/claude-agent-sdk-typescript/issues/144))
**Fix**: Downgrade to v0.2.7 or set `ANTHROPIC_BASE_URL` as environment variable before process start instead of via `options.env`.

### #7: SDK MCP servers fail from concurrent query() calls
**Error**: Second+ concurrent queries timeout after 60s with "MCP error -32001: Request timed out" ([#122](https://github.com/anthropics/claude-agent-sdk-typescript/issues/122))
**Fix**: Use stdio MCP servers instead of `createSdkMcpServer()` for concurrent queries.

### #8: Missing @anthropic-ai/sdk dependency causes type loss
**Error**: TypeScript types resolve as `any` for SDK messages/events ([#121](https://github.com/anthropics/claude-agent-sdk-typescript/issues/121))
**Fix**: `npm install @anthropic-ai/sdk` as peer dependency.

### #9: Ripgrep binary lacks execute permission on VS Code Remote SSH
**Error**: Commands/agents from `.claude/commands/` and `.claude/agents/` silently not discovered on Linux remote ([#129](https://github.com/anthropics/claude-agent-sdk-typescript/issues/129))
**Fix**: VS Code extensions should `chmod +x` ripgrep binaries at activation:
```typescript
const rgPath = path.join(extensionPath, "node_modules/@anthropic-ai/claude-agent-sdk/vendor/ripgrep/x64-linux/rg");
await fs.promises.chmod(rgPath, 0o755);
```

### #10: MCP tool calls timeout at 5 minutes despite MCP_TOOL_TIMEOUT
**Error**: MCP tools timeout at exactly 300s with "fetch failed" even with `MCP_TOOL_TIMEOUT=1200000` ([#118](https://github.com/anthropics/claude-agent-sdk-typescript/issues/118))
**Cause**: Hardcoded undici `headersTimeout` overrides environment variable.
**Status**: No workaround available — long-running MCP tools (>5min) not currently supported.

### #11: Opaque "process exited with code 1" errors
**Error**: Cryptic crash without detail when input is too long, session expired, or other failures ([#106](https://github.com/anthropics/claude-agent-sdk-typescript/issues/106))
**Impact**: Difficult to debug production issues — all errors look identical.
**Workaround**: Enable `debug: true` or `debugFile: 'debug.log'` option to capture detailed logs. See [Debugging section](#debugging--error-handling).

### #12: permissionDecision: 'deny' causes missing tool_result, API 400 error
**Error**: `invalid_request_error` - "tool_use ids were found without tool_result blocks" ([#170](https://github.com/anthropics/claude-agent-sdk-typescript/issues/170))
**Cause**: PreToolUse hook with `permissionDecision: 'deny'` blocks tool execution but doesn't generate a corresponding `tool_result`, breaking conversation history.
**Fix**: Use `permissionDecision: 'allow'` with modified input instead:
```typescript
return {
  hookSpecificOutput: {
    hookEventName: 'PreToolUse',
    permissionDecision: 'allow',
    updatedInput: { command: `echo "BLOCKED: ${reason}"` }
  }
};
```

### #13: thinking: { type: 'adaptive' } silently disables thinking
**Error**: Zero thinking blocks despite `thinking: { type: 'adaptive' }` configured ([#168](https://github.com/anthropics/claude-agent-sdk-typescript/issues/168))
**Cause**: SDK sets `maxThinkingTokens = undefined` for adaptive mode, preventing `--max-thinking-tokens` CLI flag from being passed.
**Fix**: Use `thinking: { type: 'enabled', budgetTokens: 10000 }` or deprecated `maxThinkingTokens` option:
```typescript
// WRONG (silently disables thinking)
thinking: { type: 'adaptive' }, effort: 'medium'

// CORRECT (explicit budget)
thinking: { type: 'enabled', budgetTokens: 10000 }, effort: 'medium'

// ALSO WORKS (deprecated but functional)
maxThinkingTokens: 10000, effort: 'medium'
```

### #14: HTTP MCP servers fail behind corporate proxies
**Error**: "The socket connection was closed unexpectedly" when HTTP MCP servers used behind corporate proxy with SSL inspection ([#169](https://github.com/anthropics/claude-agent-sdk-typescript/issues/169))
**Cause**: Bundled MCP transport doesn't propagate proxy configuration from environment variables (HTTP_PROXY, HTTPS_PROXY, NODE_EXTRA_CA_CERTS).
**Workaround**: Use SSE-type MCP servers or stdio MCP servers instead of HTTP type.

### #15: ANTHROPIC_LOG=debug corrupts SDK protocol
**Error**: `CLI output was not valid JSON` when `ANTHROPIC_LOG=debug` is set ([#157](https://github.com/anthropics/claude-agent-sdk-typescript/issues/157))
**Cause**: Debug logs written to stdout corrupt JSON protocol between SDK and CLI subprocess.
**Fix**: Don't use `ANTHROPIC_LOG=debug` with SDK. Use `debug: true` or `debugFile` option instead.

### #16: MCP server responses don't reset activity timer
**Error**: "Stream closed" errors or excessive query durations with SDK MCP servers ([#114](https://github.com/anthropics/claude-agent-sdk-typescript/issues/114))
**Cause**: `sendMcpServerMessageToCli()` resolves MCP responses but doesn't reset `lastActivityTime`, causing premature timeouts or unnecessary waits.
**Fix**: Increase `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` (e.g., 120000 for 120s) or apply [community patch](https://github.com/anthropics/claude-agent-sdk-typescript/issues/114#issuecomment-2693849829).

### #17: SDK fails to discover CLI when bundled with bun build
**Error**: `Claude Code executable not found at /$bunfs/root/cli.js` ([#150](https://github.com/anthropics/claude-agent-sdk-typescript/issues/150))
**Cause**: `import.meta.url` resolves to virtual filesystem path when bundled, where CLI binary doesn't physically exist.
**Workaround**: Set `pathToClaudeCodeExecutable` option explicitly to the physical CLI path, or avoid bundling the SDK.

### #18: unstable_v2_createSession() doesn't support plugins option
**Error**: Plugins silently ignored when using v2 session API ([#171](https://github.com/anthropics/claude-agent-sdk-typescript/issues/171))
**Cause**: `SDKSessionOptions` type doesn't include `plugins` field, so `--plugin-dir` CLI argument is never passed to Claude Code process.
**Workaround**: Use `query()` API instead of v2 sessions if you need plugin support. Plugins work correctly with the standard `query()` API.

### #19: AgentDefinition.tools and disallowedTools not enforced for subagents
**Error**: Subagents can call tools they shouldn't have access to, leading to infinite recursion ([#172](https://github.com/anthropics/claude-agent-sdk-typescript/issues/172), [#163](https://github.com/anthropics/claude-agent-sdk-typescript/issues/163))
**Cause**: CLI doesn't map `AgentDefinition.tools` to `--allowedTools` / `--disallowedTools` flags when spawning subagent child processes.
**Workaround**: Use `canUseTool` callback to block disallowed tools (see [Subagents section](#tool-enforcement-warning)).

### #20: Structured output with Zod requires draft-07 target
**Error**: `structured_output` is `undefined` despite setting `outputFormat` with Zod schema ([#105](https://github.com/anthropics/claude-agent-sdk-typescript/issues/105))
**Cause**: Zod's `toJSONSchema()` generates draft-2020-12 by default, but Claude requires JSON Schema draft-07.
**Fix**: Specify `target: "draft-07"` when calling `toJSONSchema()`:
```typescript
const schema = z.toJSONSchema(MySchema, { target: "draft-07" });
// Or manually remove $schema field:
const schema = z.toJSONSchema(MySchema);
delete schema.$schema;
```

### #21: unstable_v2_createSession() ignores critical options
**Error**: V2 session API silently ignores `permissionMode`, `cwd`, `settingSources`, `allowedTools`, `disallowedTools` ([#176](https://github.com/anthropics/claude-agent-sdk-typescript/issues/176))
**Cause**: `SessionImpl` constructor hardcodes these values instead of passing them from `SDKSessionOptions` to the `ProcessTransport`.
**Impact**: Breaks headless/server deployments requiring permission bypass, custom working directories, or CLAUDE.md loading.
**Workaround**: Manually patch `sdk.mjs` (~line 8597) to use `options` values with nullish coalescing:
```typescript
const transport = new ProcessTransport({
  permissionMode: options.permissionMode ?? "default",
  allowDangerouslySkipPermissions: options.allowDangerouslySkipPermissions ?? false,
  settingSources: options.settingSources ?? [],
  allowedTools: options.allowedTools ?? [],
  disallowedTools: options.disallowedTools ?? [],
  mcpServers: options.mcpServers ?? {},
  cwd: options.cwd,
  // ... rest of config
});
```

### #22: Large MCP tool output forces filesystem tool dependency
**Error**: When MCP tools return ≥180KB output, SDK truncates response and saves full output to local file, then agent attempts to read file using `Bash`/filesystem tools ([#175](https://github.com/anthropics/claude-agent-sdk-typescript/issues/175))
**Impact**: Breaks security-hardened deployments where filesystem tools are intentionally disabled. No configuration to prevent this behavior.
**Current behavior**: Output message shows: `Output too large (182.9KB). Full output saved to: ~/.claude/projects/.../tool-results/<id>.json`
**Status**: No workaround available. Feature request for configuration option to disable file persistence or handle large outputs without filesystem tools.

---

## Changelog Highlights (v0.2.12 → v0.2.44)

| Version | Change |
|---------|--------|
| v0.2.44 | Updated to parity with Claude Code v2.1.44 |
| v0.2.43 | Previous release (2026-02-14) |
| v0.2.33 | `TeammateIdle`/`TaskCompleted` hook events; custom `sessionId` option |
| v0.2.31 | `stop_reason` field on result messages |
| v0.2.30 | `debug`/`debugFile` options; PDF page reading |
| v0.2.27 | MCP tool `annotations` support |
| v0.2.23 | Structured output validation fix |
| v0.2.21 | `reconnectMcpServer()`, `toggleMcpServer()`, `disabled` MCP status |
| v0.2.15 | `close()` method on Query; notification hooks |

---

**Last verified**: 2026-02-17 | **SDK version**: 0.2.44
