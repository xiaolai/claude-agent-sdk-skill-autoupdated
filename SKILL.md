---
name: claude-agent-sdk
description: |
  Build autonomous AI agents with Claude Agent SDK v0.2.39. Covers the complete TypeScript API: query(), hooks, subagents, MCP, permissions, sandbox, structured outputs, and sessions.

  Use when: building AI agents, configuring MCP servers, setting up permissions/hooks, using structured outputs, troubleshooting SDK errors, or working with subagents.
user-invocable: true
---

# Claude Agent SDK Reference (v0.2.39)

**Package**: `@anthropic-ai/claude-agent-sdk@0.2.39`
**Docs**: https://platform.claude.com/docs/en/agent-sdk/overview
**Repo**: https://github.com/anthropics/claude-agent-sdk-typescript
**Migration**: Renamed from `@anthropic-ai/claude-code`. See [migration guide](https://platform.claude.com/docs/en/agent-sdk/migration-guide).

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

### `tool()`

Creates type-safe MCP tool definitions with Zod schemas.

```typescript
import { tool } from "@anthropic-ai/claude-agent-sdk";

function tool<Schema extends ZodRawShape>(
  name: string,
  description: string,
  inputSchema: Schema,
  handler: (args: z.infer<ZodObject<Schema>>, extra: unknown) => Promise<CallToolResult>
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

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `model` | `string` | CLI default | Claude model to use |
| `cwd` | `string` | `process.cwd()` | Working directory |
| `allowedTools` | `string[]` | All tools | Allowed tool names |
| `disallowedTools` | `string[]` | `[]` | Blocked tool names |
| `tools` | `string[] \| { type: 'preset', preset: 'claude_code' }` | — | Tool configuration |
| `permissionMode` | `PermissionMode` | `'default'` | `'default' \| 'acceptEdits' \| 'bypassPermissions' \| 'plan'` |
| `canUseTool` | `CanUseTool` | — | Custom permission callback |
| `systemPrompt` | `string \| { type: 'preset', preset: 'claude_code', append?: string }` | minimal | System prompt |
| `settingSources` | `SettingSource[]` | `[]` | `'user' \| 'project' \| 'local'` |
| `agents` | `Record<string, AgentDefinition>` | — | Subagent definitions |
| `mcpServers` | `Record<string, McpServerConfig>` | `{}` | MCP server configs |
| `hooks` | `Partial<Record<HookEvent, HookCallbackMatcher[]>>` | `{}` | Hook callbacks |
| `outputFormat` | `{ type: 'json_schema', schema: JSONSchema }` | — | Structured output schema |
| `resume` | `string` | — | Session ID to resume |
| `forkSession` | `boolean` | `false` | Fork when resuming |
| `continue` | `boolean` | `false` | Continue most recent conversation |
| `sessionId` | `string` | auto | Custom UUID for session (v0.2.33) |
| `resumeSessionAt` | `string` | — | Resume at specific message UUID |
| `maxTurns` | `number` | — | Max conversation turns |
| `maxBudgetUsd` | `number` | — | Max budget in USD |
| `maxThinkingTokens` | `number` | — | Max thinking tokens |
| `fallbackModel` | `string` | — | Fallback model on failure |
| `betas` | `SdkBeta[]` | `[]` | Beta features (e.g., `['context-1m-2025-08-07']`) |
| `sandbox` | `SandboxSettings` | — | Sandbox configuration |
| `enableFileCheckpointing` | `boolean` | `false` | Enable file rollback |
| `plugins` | `SdkPluginConfig[]` | `[]` | `{ type: 'local', path: string }` |
| `additionalDirectories` | `string[]` | `[]` | Extra directories for Claude to access |
| `env` | `Dict<string>` | `process.env` | Environment variables |
| `abortController` | `AbortController` | — | Cancellation controller |
| `allowDangerouslySkipPermissions` | `boolean` | `false` | Required with `bypassPermissions` |
| `includePartialMessages` | `boolean` | `false` | Include streaming partial messages |
| `debug` | `boolean` | — | Enable debug logging (v0.2.30) |
| `debugFile` | `string` | — | Debug log file path (v0.2.30) |
| `strictMcpConfig` | `boolean` | `false` | Strict MCP validation |
| `stderr` | `(data: string) => void` | — | stderr callback |
| `executable` | `'bun' \| 'deno' \| 'node'` | auto | JS runtime |

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
await q.setMaxThinkingTokens(4096);         // Change thinking budget

// Introspection
await q.supportedModels();                  // List available models
await q.supportedCommands();                // List slash commands
await q.mcpServerStatus();                  // MCP server status
await q.accountInfo();                      // Account info

// File checkpointing (requires enableFileCheckpointing: true)
await q.rewindFiles(userMessageUuid);       // Rewind to checkpoint
```

---

## Message Types

```typescript
type SDKMessage =
  | SDKAssistantMessage     // type: 'assistant' — agent responses
  | SDKUserMessage          // type: 'user' — user input
  | SDKResultMessage        // type: 'result' — final result
  | SDKSystemMessage        // type: 'system', subtype: 'init' — session init
  | SDKPartialAssistantMessage  // type: 'stream_event' (includePartialMessages)
  | SDKCompactBoundaryMessage   // type: 'system', subtype: 'compact_boundary'
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
```

### SDKSystemMessage (init)

```typescript
{ type: 'system', subtype: 'init', session_id, model, tools: string[],
  cwd, mcp_servers: { name, status }[], permissionMode, slash_commands,
  apiKeySource, output_style }
```

### SDKAssistantMessage

```typescript
{ type: 'assistant', uuid, session_id, message: APIAssistantMessage,
  parent_tool_use_id: string | null }
```

### Streaming Pattern

```typescript
let sessionId: string;
for await (const message of query({ prompt: "...", options })) {
  switch (message.type) {
    case 'system':
      if (message.subtype === 'init') sessionId = message.session_id;
      break;
    case 'assistant':
      console.log(message.message);
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
      PreToolUse: [
        { matcher: 'Write|Edit', hooks: [protectFiles] },
        { matcher: '^mcp__', hooks: [logMcpCalls] },
        { hooks: [globalLogger] }  // no matcher = all tools
      ],
      Stop: [{ hooks: [cleanup] }],  // matchers ignored for lifecycle hooks
      Notification: [{ hooks: [notifySlack] }]
    }
  }
});
```

### Hook Return Values

```typescript
// Allow (empty = allow)
return {};

// Block a tool (PreToolUse only)
return {
  hookSpecificOutput: {
    hookEventName: input.hook_event_name,
    permissionDecision: 'deny',  // 'allow' | 'deny' | 'ask'
    permissionDecisionReason: 'Blocked: dangerous command'
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

// Inject context (PreToolUse, PostToolUse, UserPromptSubmit, SessionStart)
return {
  hookSpecificOutput: {
    hookEventName: input.hook_event_name,
    additionalContext: 'Extra instructions for Claude'
  }
};

// Stop agent
return { continue: false, stopReason: 'Budget exceeded' };

// Inject system message
return { systemMessage: 'Remember: /etc is protected' };
```

### Hook Input Fields

Common fields on all hooks: `session_id`, `transcript_path`, `cwd`, `permission_mode`

| Field | Hooks |
|-------|-------|
| `tool_name`, `tool_input` | PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest |
| `tool_response` | PostToolUse |
| `error`, `is_interrupt` | PostToolUseFailure |
| `prompt` | UserPromptSubmit |
| `stop_hook_active` | Stop, SubagentStop |
| `agent_id`, `agent_type` | SubagentStart |
| `trigger`, `custom_instructions` | PreCompact |
| `source` | SessionStart (`'startup' \| 'resume' \| 'clear' \| 'compact'`) |
| `reason` | SessionEnd |
| `message`, `title` | Notification |
| `permission_suggestions` | PermissionRequest |

---

## Permissions

### PermissionMode

```typescript
type PermissionMode = 'default' | 'acceptEdits' | 'bypassPermissions' | 'plan';
```

### canUseTool

```typescript
type CanUseTool = (
  toolName: string,
  input: ToolInput,
  options: { signal: AbortSignal; suggestions?: PermissionUpdate[] }
) => Promise<PermissionResult>;

type PermissionResult =
  | { behavior: 'allow'; updatedInput: ToolInput; updatedPermissions?: PermissionUpdate[] }
  | { behavior: 'deny'; message: string; interrupt?: boolean };
```

Example:

```typescript
canUseTool: async (toolName, input, { signal }) => {
  if (['Read', 'Grep', 'Glob'].includes(toolName)) {
    return { behavior: 'allow', updatedInput: input };
  }
  if (toolName === 'Bash' && /rm -rf|dd if=|mkfs/.test(input.command)) {
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

---

## Subagents

### AgentDefinition

```typescript
type AgentDefinition = {
  description: string;   // When to use (used by main agent for delegation)
  prompt: string;        // System prompt
  tools?: string[];      // Allowed tools (inherits if omitted)
  model?: 'sonnet' | 'opus' | 'haiku' | 'inherit';
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
        model: "haiku"
      }
    }
  }
})) { ... }
```

### Subagent Cleanup Warning

Subagents don't auto-stop when the parent stops ([#132](https://github.com/anthropics/claude-agent-sdk-typescript/issues/132)). This causes orphan processes and potential OOM ([#4850](https://github.com/anthropics/claude-code/issues/4850)).

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

Auto-termination tracked at [#142](https://github.com/anthropics/claude-agent-sdk-typescript/issues/142).

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
  };
  ignoreViolations?: { file?: string[]; network?: string[] };
  enableWeakerNestedSandbox?: boolean;
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
```

V2 preview interface available — see [TypeScript V2 preview docs](https://platform.claude.com/docs/en/agent-sdk/typescript-v2-preview).

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
**Workaround**: Enable `debug: true` or `debugFile: 'debug.log'` option to capture detailed logs.

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
**Fix**: Use deprecated `maxThinkingTokens` option directly instead of `thinking`:
```typescript
// WRONG (disables thinking)
thinking: { type: 'adaptive' }, effort: 'medium'

// CORRECT
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
**Workaround**: Use `PreToolUse` hook with `canUseTool` callback to block disallowed tools:
```typescript
const activeSubagentSessions = new Map<string, string>();

const options = {
  hooks: {
    SubagentStart: [(input) => {
      activeSubagentSessions.set(input.session_id, input.agent_name);
      return { continue: true };
    }],
  },
  canUseTool: async ({ tool_name, session_id }) => {
    if (tool_name === "Task" && activeSubagentSessions.has(session_id)) {
      return {
        allowed: false,
        reason: "Task tool is not allowed in subagents"
      };
    }
    return { allowed: true };
  }
};
```

---

## Changelog Highlights (v0.2.12 → v0.2.39)

| Version | Change |
|---------|--------|
| v0.2.33 | `TeammateIdle`/`TaskCompleted` hook events; custom `sessionId` option |
| v0.2.31 | `stop_reason` field on result messages |
| v0.2.30 | `debug`/`debugFile` options; PDF page reading |
| v0.2.27 | MCP tool `annotations` support |
| v0.2.23 | Structured output validation fix |
| v0.2.21 | `reconnectMcpServer()`, `toggleMcpServer()`, `disabled` MCP status |
| v0.2.15 | `close()` method on Query; notification hooks |

---

**Last verified**: 2026-02-13 | **SDK version**: 0.2.39
