# Claude Agent SDK — Python Reference (v0.1.81)

**Package**: `claude-agent-sdk==0.1.81` (PyPI)
**Docs**: https://platform.claude.com/docs/en/agent-sdk/python
**Repo**: https://github.com/anthropics/claude-agent-sdk-python
**Requires**: Python 3.10+
**Migration**: Renamed from `claude-code-sdk`. `ClaudeCodeOptions` is now `ClaudeAgentOptions`.

---

## Table of Contents

- [Breaking Changes](#breaking-changes-v010)
- [Core API](#core-api) — `query()`, `ClaudeSDKClient`, `@tool`, `create_sdk_mcp_server()`
- [Options](#options) — Core, Tools & Permissions, Models & Output, Sessions, MCP & Agents, Advanced
- [Client Methods](#client-methods) — `ClaudeSDKClient` lifecycle and control
- [Message Types](#message-types) — `Message` union, task messages, content blocks, errors
- [Hooks](#hooks) — 10 hook events, matchers, return values, async hooks
- [Permissions](#permissions) — 6 modes, `can_use_tool` callback
- [MCP Servers](#mcp-servers) — stdio, HTTP, SSE, SDK in-process
- [Subagents](#subagents) — `AgentDefinition`, tool enforcement
- [Extended Thinking](#extended-thinking) — `ThinkingConfig`, `effort`
- [Structured Outputs](#structured-outputs)
- [Sandbox](#sandbox)
- [Sessions](#sessions) — resume, fork, listing, mutations, [Session Store](#session-store)
- [Debugging & Error Handling](#debugging--error-handling)
- [Known Issues](#known-issues)
- [Changelog Highlights](#changelog-highlights)

---

## Breaking Changes (v0.1.0)

1. **No default system prompt** — SDK uses minimal prompt. Use `system_prompt={"type": "preset", "preset": "claude_code"}` for old behavior. Add `"append": "extra text"` to extend the preset.
2. **No filesystem settings loaded** — `setting_sources` defaults to `None`. Add `setting_sources=["project"]` to load CLAUDE.md.
3. **`ClaudeCodeOptions` renamed** — Now `ClaudeAgentOptions`.

---

## Core API

### `query()`

One-shot function. Creates a new session per call. Returns an async iterator of messages.

```python
from claude_agent_sdk import query, ClaudeAgentOptions

async def query(
    *,
    prompt: str | AsyncIterable[dict[str, Any]],
    options: ClaudeAgentOptions | None = None,
    transport: Transport | None = None,  # Custom transport (advanced, for testing)
) -> AsyncIterator[Message]: ...
```

**Streaming input**: `prompt` accepts `AsyncIterable[dict]` for real-time, multi-message input:

```python
import asyncio
from claude_agent_sdk import query

async def prompt_stream():
    yield {"type": "text", "text": "Analyze this data:"}
    await asyncio.sleep(0.5)
    yield {"type": "text", "text": "Temperature: 25C, Humidity: 60%"}

async for message in query(prompt=prompt_stream()):
    print(message)
```

#### Basic example

```python
import asyncio
from claude_agent_sdk import query, ClaudeAgentOptions

async def main():
    options = ClaudeAgentOptions(
        system_prompt="You are an expert Python developer",
        permission_mode="acceptEdits",
        cwd="/home/user/project",
    )
    async for message in query(prompt="Create a Python web server", options=options):
        print(message)

asyncio.run(main())
```

### `ClaudeSDKClient`

Stateful client. Maintains a conversation session across multiple exchanges. Supports interrupts, hooks, and custom tools.

```python
from claude_agent_sdk import ClaudeSDKClient

class ClaudeSDKClient:
    def __init__(self, options: ClaudeAgentOptions | None = None, transport: Transport | None = None) -> None: ...
    async def connect(self, prompt: str | AsyncIterable[dict] | None = None) -> None: ...
    async def query(self, prompt: str | AsyncIterable[dict], session_id: str = "default") -> None: ...
    async def receive_messages(self) -> AsyncIterator[Message]: ...
    async def receive_response(self) -> AsyncIterator[Message]: ...
    async def interrupt(self) -> None: ...
    async def rewind_files(self, user_message_id: str) -> None: ...
    async def set_permission_mode(self, mode: PermissionMode) -> None: ...
    async def set_model(self, model: str | None = None) -> None: ...
    async def get_mcp_status(self) -> McpStatusResponse: ...
    async def get_server_info(self) -> dict[str, Any] | None: ...
    async def reconnect_mcp_server(self, server_name: str) -> None: ...
    async def toggle_mcp_server(self, server_name: str, enabled: bool) -> None: ...
    async def stop_task(self, task_id: str) -> None: ...
    async def get_context_usage(self) -> ContextUsageResponse: ...
    async def disconnect(self) -> None: ...
```

Context manager support for automatic lifecycle management:

```python
async with ClaudeSDKClient(options=options) as client:
    await client.query("Hello Claude")
    async for message in client.receive_response():
        print(message)
```

#### `query()` vs `ClaudeSDKClient` comparison

| Feature             | `query()`                     | `ClaudeSDKClient`                  |
|---------------------|-------------------------------|------------------------------------|
| **Session**         | Creates new session each time | Reuses same session                |
| **Conversation**    | Single exchange               | Multiple exchanges in same context |
| **Connection**      | Managed automatically         | Manual control                     |
| **Streaming Input** | Yes                           | Yes                                |
| **Interrupts**      | No                            | Yes                                |
| **Hooks**           | Yes (via `options`)           | Yes                                |
| **Custom Tools**    | Yes (v0.1.81+: string prompts fully supported; older versions require AsyncIterable — see [#14](#14-sdk-mcp-servers-completely-non-functional-with-string-prompts)) | Yes |
| **Continue Chat**   | No (new session each time)    | Yes (maintains conversation)       |

### `@tool()`

Decorator for defining MCP tools.

```python
from claude_agent_sdk import tool, ToolAnnotations  # ToolAnnotations re-exported from mcp.types
from typing import Any

def tool(
    name: str,
    description: str,
    input_schema: type | dict[str, Any],
    annotations: ToolAnnotations | None = None
) -> Callable[[Callable[[Any], Awaitable[dict[str, Any]]]], SdkMcpTool[Any]]: ...
```

**Input schema options**:

1. **Simple type mapping** (recommended):
   ```python
   {"city": str, "count": int, "enabled": bool}
   ```

2. **With per-parameter descriptions** using `typing.Annotated` (added v0.1.81):
   ```python
   from typing import Annotated
   {"city": Annotated[str, "The city name to look up"], "count": Annotated[int, "Max results"]}
   ```
   Also works with `TypedDict` schemas: annotate fields with `Annotated[type, "description"]`.

3. **JSON Schema format** (for complex validation):
   ```python
   {
       "type": "object",
       "properties": {
           "text": {"type": "string"},
           "count": {"type": "integer", "minimum": 0},
       },
       "required": ["text"],
   }
   ```

**`annotations` parameter** — pass `ToolAnnotations` (re-exported from `mcp.types`) to set MCP tool metadata. The `maxResultSizeChars` attribute controls the CLI's spill threshold for large tool results (fixed in v0.1.81, [#756](https://github.com/anthropics/claude-agent-sdk-python/issues/756)):

```python
from mcp.types import ToolAnnotations

@tool(
    "fetch_large_doc",
    "Fetch a potentially large document",
    {"url": str},
    annotations=ToolAnnotations(maxResultSizeChars=500_000),  # Raise spill limit for this tool
)
async def fetch_large_doc(args: dict[str, Any]) -> dict[str, Any]:
    ...
```

Other `ToolAnnotations` fields (`readOnly`, `destructive`, `openWorld`) are passed to the CLI as standard MCP metadata that Claude uses to understand tool behavior.

Handler returns: `{"content": [{"type": "text", "text": "..."}], "is_error": bool}`

```python
@tool("greet", "Greet a user", {"name": str})
async def greet(args: dict[str, Any]) -> dict[str, Any]:
    return {"content": [{"type": "text", "text": f"Hello, {args['name']}!"}]}
```

### `create_sdk_mcp_server()`

Creates an in-process MCP server from `@tool`-decorated functions.

```python
from claude_agent_sdk import create_sdk_mcp_server

def create_sdk_mcp_server(
    name: str,
    version: str = "1.0.0",
    tools: list[SdkMcpTool[Any]] | None = None
) -> McpSdkServerConfig: ...
```

```python
server = create_sdk_mcp_server(name="calculator", version="2.0.0", tools=[add, multiply])
```

### `SdkMcpTool`

The dataclass returned by the `@tool` decorator (also exported from `claude_agent_sdk`):

```python
from claude_agent_sdk import SdkMcpTool
from typing import TypeVar, Generic, Any
from collections.abc import Awaitable, Callable
from mcp.types import ToolAnnotations

T = TypeVar("T")

@dataclass
class SdkMcpTool(Generic[T]):
    name: str                                          # Unique tool identifier
    description: str                                   # Human-readable description
    input_schema: type[T] | dict[str, Any]             # Type or JSON Schema dict
    handler: Callable[[T], Awaitable[dict[str, Any]]]  # Async tool implementation
    annotations: ToolAnnotations | None = None         # Optional MCP tool annotations
```

---

## Options

### Core Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `model` | `str \| None` | `None` | Claude model to use |
| `cwd` | `str \| Path \| None` | `None` | Working directory |
| `system_prompt` | `str \| SystemPromptPreset \| SystemPromptFile \| None` | `None` | System prompt, preset dict, or file reference (see [`SystemPromptPreset`](#systempromptsettings)) |
| `setting_sources` | `list[SettingSource] \| None` | `None` | Which settings files to load: `"user"` (`~/.claude/`), `"project"` (`.claude/` in cwd), `"local"`. Empty list silently ignored — see [#40](#40-setting_sources-silently-ignored--no-way-to-fully-isolate-from-filesystem-settings) |
| `env` | `dict[str, str]` | `{}` | Environment variables. Set `CLAUDE_AGENT_SDK_CLIENT_APP="my-app/1.0.0"` to identify your app in the User-Agent header. |
| `cli_path` | `str \| Path \| None` | `None` | Custom path to Claude Code CLI |

#### `SystemPromptPreset` / `SystemPromptFile` / `ToolsPreset`

```python
class SystemPromptPreset(TypedDict):
    type: Literal["preset"]
    preset: Literal["claude_code"]
    append: NotRequired[str]                     # Optional text appended after the preset
    exclude_dynamic_sections: NotRequired[bool]  # Strip per-user dynamic sections (cwd, memory, git) for cross-user cache hits (added v0.1.57)

class ToolsPreset(TypedDict):
    type: Literal["preset"]
    preset: Literal["claude_code"]  # Enable the full Claude Code toolset

class SystemPromptFile(TypedDict):
    type: Literal["file"]
    path: str                        # Path to a file containing the system prompt
```

#### `TaskBudget`

```python
from claude_agent_sdk.types import TaskBudget

class TaskBudget(TypedDict):
    total: int   # Maximum token budget for the task
```

Use `task_budget` to signal the model to pace its tool use and wrap up before hitting the limit:

```python
options = ClaudeAgentOptions(
    task_budget={"total": 50_000}  # Model paces itself to stay within 50k tokens
)
```

#### `SdkBeta`

```python
from claude_agent_sdk.types import SdkBeta

SdkBeta = Literal["context-1m-2025-08-07"]  # Enable 1M token context window (Sonnet 4/4.5 only)
```

Use these to opt in to the full Claude Code system prompt and/or toolset:

```python
options = ClaudeAgentOptions(
    # Full Claude Code system prompt (replaces SDK's minimal default)
    system_prompt={"type": "preset", "preset": "claude_code"},

    # With extra instructions appended after the preset
    system_prompt={"type": "preset", "preset": "claude_code", "append": "Always prefer TypeScript."},

    # Load system prompt from a file
    system_prompt={"type": "file", "path": "/path/to/system_prompt.txt"},

    # Enable the full Claude Code toolset preset
    tools={"type": "preset", "preset": "claude_code"},
)
```

### Tools & Permissions

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `tools` | `list[str] \| ToolsPreset \| None` | `None` | Tool configuration |
| `allowed_tools` | `list[str]` | `[]` | Allowed tool names |
| `disallowed_tools` | `list[str]` | `[]` | Blocked tool names |
| `permission_mode` | `PermissionMode \| None` | `None` | See [Permissions](#permissions) for all 6 modes |
| `can_use_tool` | `CanUseTool \| None` | `None` | Custom permission callback |
| `permission_prompt_tool_name` | `str \| None` | `None` | Route permission prompts through a named MCP tool |

### Models & Output

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `output_format` | `dict[str, Any] \| None` | `None` | `{"type": "json_schema", "schema": dict}` |
| `max_thinking_tokens` | `int \| None` | `None` | **Deprecated** — use `thinking` instead |
| `thinking` | `ThinkingConfig \| None` | `None` | Extended thinking configuration (adaptive/enabled/disabled) |
| `effort` | `Literal["low", "medium", "high", "xhigh", "max"] \| None` | `None` | Effort level for thinking depth (`"xhigh"` = extended reasoning on Opus 4.7+; falls back to `"high"` on other models) |
| `fallback_model` | `str \| None` | `None` | Fallback model on failure |
| `betas` | `list[SdkBeta]` | `[]` | Beta features (e.g., `["context-1m-2025-08-07"]`) |
| `include_partial_messages` | `bool` | `False` | Include streaming partial `StreamEvent` messages |
| `include_hook_events` | `bool` | `False` | Emit `HookEventMessage` objects (subtype `"hook_started"` / `"hook_response"`) into the message stream for every hook lifecycle event (matches TS SDK `includeHookEvents`) |
| `task_budget` | `TaskBudget \| None` | `None` | API-side token budget hint; model paces tool use to finish within limit (`{"total": int}`). |

### Sessions

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `resume` | `str \| None` | `None` | Session ID to resume |
| `session_id` | `str \| None` | `None` | Explicit session ID to use (instead of auto-generated UUID) |
| `fork_session` | `bool` | `False` | Fork when resuming |
| `continue_conversation` | `bool` | `False` | Continue most recent conversation |
| `max_turns` | `int \| None` | `None` | Max conversation turns (critical safety net) |
| `max_budget_usd` | `float \| None` | `None` | Max budget in USD |
| `enable_file_checkpointing` | `bool` | `False` | Enable file rollback via `rewind_files()` |
| `session_store` | `SessionStore \| None` | `None` | Mirror session transcripts to external storage and enable store-backed resume (see [Session Store](#session-store)) |
| `session_store_flush` | `SessionStoreFlushMode` | `"batched"` | When to flush mirrored entries to `session_store`. `"batched"` (default) coalesces entries and flushes once per turn or when the buffer exceeds 500 entries / 1 MiB; `"eager"` triggers a background flush after every frame for near-real-time delivery. Ignored when `session_store` is `None`. (added v0.1.81) |
| `load_timeout_ms` | `int` | `60000` | Timeout in ms for `session_store.load()`/`list_subkeys()` during resume; `0` = immediate timeout |

### MCP & Agents

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `mcp_servers` | `dict[str, McpServerConfig] \| str \| Path` | `{}` | MCP server configs or path to config file |
| `strict_mcp_config` | `bool` | `False` | When `True`, ignore all other MCP sources (project `.mcp.json`, user/global settings, plugins) and use only `mcp_servers`. Maps to `--strict-mcp-config`. |
| `agents` | `dict[str, AgentDefinition] \| None` | `None` | Subagent definitions |
| `plugins` | `list[SdkPluginConfig]` | `[]` | `{"type": "local", "path": str}` |
| `skills` | `list[str] \| Literal["all"] \| None` | `None` | Skills to enable for the main session. `None` = CLI defaults apply (not "off"). `[]` = suppress all skills. `"all"` = every discovered skill. `["name", ...]` = only listed skills (name matches SKILL.md `name`/directory, or `"plugin:skill"` for plugin-qualified). SDK auto-adds `"Skill"` to `allowed_tools` and sets `setting_sources` when this is set. |

### Advanced

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `sandbox` | `SandboxSettings \| None` | `None` | Sandbox configuration |
| `hooks` | `dict[HookEvent, list[HookMatcher]] \| None` | `None` | Hook callbacks |
| `add_dirs` | `list[str \| Path]` | `[]` | Extra directories for Claude to access |
| `user` | `str \| None` | `None` | User identifier |
| `settings` | `str \| None` | `None` | Path to settings file |
| `extra_args` | `dict[str, str \| None]` | `{}` | Additional CLI arguments |
| `max_buffer_size` | `int \| None` | `None` | Maximum bytes when buffering CLI stdout |
| `stderr` | `Callable[[str], None] \| None` | `None` | stderr callback |
| `debug_stderr` | `Any` | `sys.stderr` | **Deprecated** — use `stderr` callback instead |

---

## Client Methods

### `ClaudeSDKClient` lifecycle

```python
from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions

client = ClaudeSDKClient(options=ClaudeAgentOptions(...))

# Manual lifecycle
await client.connect()                              # Start connection
await client.query("First question")                # Send prompt
async for msg in client.receive_response():          # Iterate until ResultMessage
    print(msg)
await client.query("Follow-up question")            # Continue conversation
async for msg in client.receive_response():
    print(msg)
await client.disconnect()                           # Close connection

# Context manager lifecycle (preferred)
async with ClaudeSDKClient(options) as client:
    await client.query("Hello")
    async for msg in client.receive_response():
        print(msg)
```

### Control methods

```python
await client.interrupt()                            # Interrupt current execution
await client.rewind_files(user_message_id)          # Rewind files to checkpoint
await client.set_permission_mode(mode)              # Change permission mode mid-conversation
await client.set_model(model)                       # Switch AI model mid-conversation
status = await client.get_mcp_status()              # Get MCP server connection status (returns McpStatusResponse)
info = await client.get_server_info()               # Get server initialization info
await client.reconnect_mcp_server(server_name)      # Reconnect a failed or disconnected MCP server
await client.toggle_mcp_server(server_name, True)   # Enable (True) or disable (False) an MCP server
await client.stop_task(task_id)                     # Stop a running Task; emits task_notification with status 'stopped'
usage = await client.get_context_usage()            # Get context window usage breakdown (returns ContextUsageResponse)
```

#### `ContextUsageResponse` / `ContextUsageCategory`

```python
from claude_agent_sdk import ContextUsageResponse, ContextUsageCategory

class ContextUsageCategory(TypedDict):
    name: str
    tokens: int
    color: str
    isDeferred: NotRequired[bool]

class ContextUsageResponse(TypedDict):
    categories: list[ContextUsageCategory]  # Token usage per category
    totalTokens: int                         # Total tokens in context window
    maxTokens: int                           # Effective maximum (may be reduced by autocompact buffer)
    rawMaxTokens: int                        # Raw model context window size
    percentage: float                        # Context used (0-100)
    model: str                               # Model the usage is calculated for
    isAutoCompactEnabled: bool               # Whether autocompact is enabled
    memoryFiles: list[dict[str, Any]]        # CLAUDE.md and memory files loaded
    mcpTools: list[dict[str, Any]]           # MCP tools with token counts
    agents: list[dict[str, Any]]             # Agent definitions with token counts
    gridRows: list[list[dict[str, Any]]]     # Visual grid for CLI context display
    autoCompactThreshold: NotRequired[int]   # Token threshold for autocompact trigger
    deferredBuiltinTools: NotRequired[list[dict[str, Any]]]
    systemTools: NotRequired[list[dict[str, Any]]]
    systemPromptSections: NotRequired[list[dict[str, Any]]]
    slashCommands: NotRequired[dict[str, Any]]
    skills: NotRequired[dict[str, Any]]
    messageBreakdown: NotRequired[dict[str, Any]]
    apiUsage: NotRequired[dict[str, Any] | None]  # Cumulative API usage for the session

# Example: monitor context pressure
usage = await client.get_context_usage()
print(f"Context: {usage['percentage']:.1f}% ({usage['totalTokens']}/{usage['maxTokens']} tokens)")
for cat in usage['categories']:
    print(f"  {cat['name']}: {cat['tokens']}")
```

### Iteration methods

```python
# receive_response() — yields messages until (and including) the next ResultMessage
async for msg in client.receive_response():
    print(msg)

# receive_messages() — yields all messages (does not stop at ResultMessage)
async for msg in client.receive_messages():
    print(msg)
```

**Warning**: Avoid using `break` to exit iteration early as this can cause asyncio cleanup issues. Let iteration complete naturally or use flags to track when you have found what you need.

### Multi-turn conversation example

```python
import asyncio
from claude_agent_sdk import ClaudeSDKClient, AssistantMessage, TextBlock

async def main():
    async with ClaudeSDKClient() as client:
        # Turn 1
        await client.query("What's the capital of France?")
        async for message in client.receive_response():
            if isinstance(message, AssistantMessage):
                for block in message.content:
                    if isinstance(block, TextBlock):
                        print(f"Claude: {block.text}")

        # Turn 2 — Claude remembers previous context
        await client.query("What's the population of that city?")
        async for message in client.receive_response():
            if isinstance(message, AssistantMessage):
                for block in message.content:
                    if isinstance(block, TextBlock):
                        print(f"Claude: {block.text}")

asyncio.run(main())
```

---

## Message Types

The SDK emits 6 message types:

```python
from claude_agent_sdk import (
    UserMessage, AssistantMessage, SystemMessage, ResultMessage,
    StreamEvent, RateLimitEvent
)

Message = UserMessage | AssistantMessage | SystemMessage | ResultMessage | StreamEvent | RateLimitEvent
```

### `UserMessage`

```python
@dataclass
class UserMessage:
    content: str | list[ContentBlock]
    uuid: str | None = None
    parent_tool_use_id: str | None = None
    tool_use_result: dict[str, Any] | None = None
```

### `AssistantMessage`

```python
@dataclass
class AssistantMessage:
    content: list[ContentBlock]
    model: str
    parent_tool_use_id: str | None = None
    error: AssistantMessageError | None = None
    usage: dict[str, Any] | None = None    # Per-turn token usage (added v0.1.50)
    message_id: str | None = None          # Anthropic API message ID (added v0.1.81)
    stop_reason: str | None = None         # Raw stop reason from Anthropic API (added v0.1.81)
    session_id: str | None = None          # Session this message belongs to (added v0.1.81)
    uuid: str | None = None                # Unique message identifier (added v0.1.81)

# AssistantMessageError type
AssistantMessageError = Literal[
    "authentication_failed",
    "billing_error",
    "rate_limit",
    "invalid_request",
    "server_error",
    "unknown",
]
```

### `SystemMessage`

```python
@dataclass
class SystemMessage:
    subtype: str          # 'init', 'status', 'hook_started', 'hook_progress', etc.
    data: dict[str, Any]
```

Key subtypes:
- `init` — session initialization (contains `session_id`, `model`, `tools`, `cwd`, `mcp_servers`)
- `status` — status updates (e.g., `"compacting"`)
- `hook_started` / `hook_progress` / `hook_response` — hook lifecycle
- `task_started` / `task_progress` / `task_notification` — task lifecycle (use typed subclasses below)

### `ResultMessage`

```python
@dataclass
class ResultMessage:
    subtype: str                             # 'success' | error variants
    duration_ms: int
    duration_api_ms: int
    is_error: bool
    num_turns: int
    session_id: str
    stop_reason: str | None = None           # Raw stop reason from Anthropic API
    total_cost_usd: float | None = None
    usage: dict[str, Any] | None = None
    result: str | None = None
    structured_output: Any = None
    model_usage: dict[str, Any] | None = None       # Per-model token breakdown (added v0.1.81)
    permission_denials: list[Any] | None = None     # Permission denial records (added v0.1.81)
    deferred_tool_use: DeferredToolUse | None = None  # Set when a PreToolUse hook returned permissionDecision="defer"; contains the deferred tool call
    errors: list[str] | None = None                 # Error messages from the session (added v0.1.81)
    api_error_status: int | None = None             # HTTP status code (e.g. 429, 500, 529) of the failing API call when is_error=True and subtype="success"
    uuid: str | None = None                         # Unique message identifier (added v0.1.81)
```

#### `DeferredToolUse`

Populated in `ResultMessage.deferred_tool_use` when a `PreToolUse` hook returns `permissionDecision: "defer"`. The run stops and the caller can inspect the deferred call and decide whether to resume.

```python
from claude_agent_sdk import DeferredToolUse

@dataclass
class DeferredToolUse:
    id: str                    # Tool call ID
    name: str                  # Tool name that was deferred
    input: dict[str, Any]      # Tool input that was deferred
```

Result subtypes:
- `success` — normal completion
- `error_max_turns` — hit `max_turns` limit
- `error_max_budget_usd` — hit `max_budget_usd` limit
- `error_during_execution` — runtime error
- `error_max_structured_output_retries` — schema validation failed after retries

### `StreamEvent`

Only received when `include_partial_messages=True`.

```python
@dataclass
class StreamEvent:
    uuid: str
    session_id: str
    event: dict[str, Any]                    # Raw Anthropic API stream event
    parent_tool_use_id: str | None = None
```

### `RateLimitEvent`

Emitted whenever the CLI detects a rate limit status change (e.g., from `allowed` to `allowed_warning`). Use this to warn users before they hit a hard limit or to gracefully back off when rejected.

```python
from claude_agent_sdk import RateLimitEvent, RateLimitInfo

@dataclass
class RateLimitEvent:
    rate_limit_info: RateLimitInfo
    uuid: str
    session_id: str

@dataclass
class RateLimitInfo:
    status: RateLimitStatus                    # "allowed" | "allowed_warning" | "rejected"
    resets_at: int | None = None               # Unix timestamp when limit window resets
    rate_limit_type: RateLimitType | None = None  # Which rate limit window applies
    utilization: float | None = None           # Fraction consumed (0.0 – 1.0)
    overage_status: RateLimitStatus | None = None
    overage_resets_at: int | None = None
    overage_disabled_reason: str | None = None
    raw: dict[str, Any] = field(default_factory=dict)  # Full CLI payload

# Supporting literals
RateLimitStatus = Literal["allowed", "allowed_warning", "rejected"]
RateLimitType = Literal["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet", "overage"]
```

```python
# Handling rate limit events
async for msg in query(prompt="...", options=options):
    if isinstance(msg, RateLimitEvent):
        info = msg.rate_limit_info
        if info.status == "rejected":
            print(f"Rate limit hit! Resets at {info.resets_at}")
        elif info.status == "allowed_warning":
            print(f"Approaching limit: {info.utilization:.0%} used")
```

### Task Messages (SystemMessage subclasses)

Three typed subclasses of `SystemMessage` are emitted for task lifecycle events. All inherit `subtype` and `data` from `SystemMessage`, so existing `isinstance(msg, SystemMessage)` checks continue to match.

```python
from claude_agent_sdk import (
    TaskStartedMessage, TaskProgressMessage, TaskNotificationMessage,
    TaskUsage, TaskNotificationStatus
)

class TaskUsage(TypedDict):
    total_tokens: int
    tool_uses: int
    duration_ms: int

TaskNotificationStatus = Literal["completed", "failed", "stopped"]

@dataclass
class TaskStartedMessage(SystemMessage):       # subtype == "task_started"
    task_id: str
    description: str
    uuid: str
    session_id: str
    tool_use_id: str | None = None
    task_type: str | None = None

@dataclass
class TaskProgressMessage(SystemMessage):      # subtype == "task_progress"
    task_id: str
    description: str
    usage: TaskUsage
    uuid: str
    session_id: str
    tool_use_id: str | None = None
    last_tool_name: str | None = None

@dataclass
class TaskNotificationMessage(SystemMessage):  # subtype == "task_notification"
    task_id: str
    status: TaskNotificationStatus             # "completed" | "failed" | "stopped"
    output_file: str
    summary: str
    uuid: str
    session_id: str
    tool_use_id: str | None = None
    usage: TaskUsage | None = None
```

### `MirrorErrorMessage`

Emitted when a `SessionStore.append()` call fails. Non-fatal — the local transcript is already durable, so the session continues. The mirrored copy in the external store will be missing the failed batch.

```python
from claude_agent_sdk import MirrorErrorMessage
from claude_agent_sdk.types import SessionKey

@dataclass
class MirrorErrorMessage(SystemMessage):  # subtype == "mirror_error"
    key: SessionKey | None = None         # Which session failed to mirror (None if unknown)
    error: str = ""                       # Error message from the store adapter
```

**Usage**:

```python
async for msg in query(prompt="...", options=ClaudeAgentOptions(session_store=store)):
    if isinstance(msg, MirrorErrorMessage):
        print(f"Mirror error for {msg.key}: {msg.error}")
        # Session continues — local transcript is intact; external mirror may be incomplete
```

### `HookEventMessage`

Emitted when `include_hook_events=True` is set on `ClaudeAgentOptions`. The CLI emits hook lifecycle events (PreToolUse, PostToolUse, Stop, etc.) into the message stream. A subclass of `SystemMessage` — existing `isinstance(msg, SystemMessage)` checks continue to match.

```python
from claude_agent_sdk import HookEventMessage

@dataclass
class HookEventMessage(SystemMessage):
    # subtype == "hook_started" (hook begins executing)
    # subtype == "hook_response" (hook completed; data carries output, exit_code, outcome)
    hook_event_name: str = ""        # e.g. "PreToolUse", "PostToolUse", "Stop"
    session_id: str | None = None
    uuid: str | None = None
    # data: full raw event dict from CLI (inherited from SystemMessage)
```

```python
options = ClaudeAgentOptions(include_hook_events=True, hooks={...})
async for msg in query(prompt="...", options=options):
    if isinstance(msg, HookEventMessage):
        print(f"Hook lifecycle: {msg.subtype} for {msg.hook_event_name}")
```

**Usage**: Use `isinstance` to distinguish task messages from generic `SystemMessage`:

```python
from claude_agent_sdk import (
    SystemMessage, TaskStartedMessage, TaskProgressMessage, TaskNotificationMessage
)

async for msg in query(prompt="...", options=options):
    if isinstance(msg, TaskNotificationMessage):
        print(f"Task {msg.task_id} {msg.status}: {msg.summary}")
    elif isinstance(msg, TaskProgressMessage):
        print(f"Task progress: {msg.description}, tokens={msg.usage['total_tokens']}")
    elif isinstance(msg, SystemMessage):
        print(f"System: {msg.subtype}")
```

### Content Block Types

```python
ContentBlock = (
    TextBlock | ThinkingBlock | ToolUseBlock | ToolResultBlock
    | ServerToolUseBlock | ServerToolResultBlock
)

@dataclass
class TextBlock:
    text: str

@dataclass
class ThinkingBlock:
    thinking: str
    signature: str

@dataclass
class ToolUseBlock:
    id: str
    name: str
    input: dict[str, Any]

@dataclass
class ToolResultBlock:
    tool_use_id: str
    content: str | list[dict[str, Any]] | None = None
    is_error: bool | None = None

# Server-side tool blocks — tools the API executes on the model's behalf.
# They appear alongside regular ToolUseBlock/ToolResultBlock but callers
# never need to return a result for them.
ServerToolName = Literal[
    "advisor", "web_search", "web_fetch", "code_execution",
    "bash_code_execution", "text_editor_code_execution",
    "tool_search_tool_regex", "tool_search_tool_bm25",
]

@dataclass
class ServerToolUseBlock:
    id: str
    name: ServerToolName       # Discriminator — branch on this to know which server tool ran
    input: dict[str, Any]

@dataclass
class ServerToolResultBlock:
    tool_use_id: str
    content: dict[str, Any]    # Raw dict from API — inspect content["type"] for specifics
```

### Streaming Pattern

```python
import asyncio
from claude_agent_sdk import (
    query, ClaudeAgentOptions, AssistantMessage, SystemMessage,
    ResultMessage, TextBlock, ToolUseBlock
)

async def main():
    session_id = None
    async for message in query(prompt="Analyze this code", options=ClaudeAgentOptions()):
        if isinstance(message, SystemMessage):
            if message.subtype == "init":
                session_id = message.data.get("session_id")
            elif message.subtype == "status":
                print(f"Status: {message.data}")

        elif isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    print(block.text)
                elif isinstance(block, ToolUseBlock):
                    print(f"Tool: {block.name}")

        elif isinstance(message, ResultMessage):
            if message.subtype == "success":
                print(f"Done. Cost: ${message.total_cost_usd}")
                if message.structured_output:
                    print(message.structured_output)
            else:
                print(f"Error: {message.subtype}")

asyncio.run(main())
```

---

## Hooks

Hooks use **callback matchers**: an optional regex `matcher` for tool names and a list of `hooks` callbacks. Hooks work with both `query()` and `ClaudeSDKClient` via `ClaudeAgentOptions.hooks`.

### Hook Events

| Event | Fires When | Supported |
|-------|-----------|-----------|
| `PreToolUse` | Before tool execution | Yes |
| `PostToolUse` | After tool execution | Yes |
| `PostToolUseFailure` | After tool execution failure | Yes |
| `UserPromptSubmit` | User prompt received | Yes |
| `Stop` | Agent stopping | Yes |
| `SubagentStop` | Subagent completed | Yes |
| `SubagentStart` | Subagent starting | Yes |
| `PreCompact` | Before context compaction | Yes |
| `Notification` | Notification event | Yes |
| `PermissionRequest` | Permission requested | Yes |

**Not supported in Python SDK**: `Setup`, `SessionStart`, `SessionEnd`, `TeammateIdle`, `TaskCompleted`, `PostCompact` (CLI v2.1.76+ supports this, Python SDK support pending — see PR [#691](https://github.com/anthropics/claude-agent-sdk-python/issues/691)).

### Hook Callback Signature

```python
from claude_agent_sdk import HookContext, HookInput, BaseHookInput
from typing import Any

async def my_hook(
    input_data: HookInput,   # Strongly-typed union of all hook input types
    tool_use_id: str | None,
    context: HookContext
) -> dict[str, Any]:
    ...
```

**Hook input types** — use `input_data["hook_event_name"]` to discriminate:

```python
# All hook inputs share these base fields (BaseHookInput):
# session_id, transcript_path, cwd, permission_mode (optional)

# HookInput is a union of all event-specific input types:
HookInput = (
    PreToolUseHookInput        # + tool_name, tool_input, tool_use_id; agent_id/agent_type (opt, subagent context)
    | PostToolUseHookInput     # + tool_name, tool_input, tool_use_id, tool_response; agent_id/agent_type (opt)
    | PostToolUseFailureHookInput  # + tool_name, tool_input, tool_use_id, error, is_interrupt; agent_id/agent_type (opt)
    | UserPromptSubmitHookInput    # + prompt
    | StopHookInput            # + stop_hook_active
    | SubagentStopHookInput    # + stop_hook_active, agent_id, agent_transcript_path, agent_type
    | PreCompactHookInput      # + trigger ("manual"|"auto"), custom_instructions
    | NotificationHookInput    # + message, title (optional), notification_type
    | SubagentStartHookInput   # + agent_id, agent_type
    | PermissionRequestHookInput  # + tool_name, tool_input, permission_suggestions; agent_id/agent_type (opt)
)
```

> **Subagent attribution in tool-lifecycle hooks**: `agent_id` and `agent_type` are optional on `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, and `PermissionRequest` inputs. They are present when the hook fires from inside a Task-spawned subagent, and absent on the main agent thread. When multiple subagents run in parallel, their hooks interleave on the same channel — use `agent_id` to attribute each event to the correct subagent.

### Hook Configuration

```python
from claude_agent_sdk import ClaudeAgentOptions, HookMatcher, HookContext
from typing import Any

async def protect_files(input_data: dict[str, Any], tool_use_id: str | None, context: HookContext) -> dict[str, Any]:
    ...

async def log_mcp_calls(input_data: dict[str, Any], tool_use_id: str | None, context: HookContext) -> dict[str, Any]:
    ...

async def global_logger(input_data: dict[str, Any], tool_use_id: str | None, context: HookContext) -> dict[str, Any]:
    print(f"Tool used: {input_data.get('tool_name')}")
    return {}

options = ClaudeAgentOptions(
    hooks={
        "PreToolUse": [
            HookMatcher(matcher="Write|Edit", hooks=[protect_files]),
            HookMatcher(matcher="^mcp__", hooks=[log_mcp_calls]),
            HookMatcher(hooks=[global_logger]),  # no matcher = all tools
        ],
        "PostToolUse": [
            HookMatcher(hooks=[global_logger]),
        ],
        "Stop": [
            HookMatcher(hooks=[cleanup]),  # matchers ignored for lifecycle hooks
        ],
    }
)
```

### HookMatcher

```python
@dataclass
class HookMatcher:
    matcher: str | None = None     # Tool name regex (e.g., "Bash", "Write|Edit")
    hooks: list[HookCallback] = field(default_factory=list)
    timeout: float | None = None   # Timeout in seconds (default: 60)
```

### Hook Return Values

```python
# Allow (empty = allow)
return {}

# Block a tool (PreToolUse only)
return {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "Dangerous command blocked",
    }
}

# Defer a tool call (PreToolUse only) — stops the run; caller inspects ResultMessage.deferred_tool_use
# and decides whether to resume (e.g. for human-in-the-loop approval)
return {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "defer",
        "permissionDecisionReason": "Awaiting human approval for this file deletion",
    }
}

# Modify tool input (PreToolUse only, requires permissionDecision: 'allow')
return {
    "hookSpecificOutput": {
        "hookEventName": input_data["hook_event_name"],
        "permissionDecision": "allow",
        "updatedInput": {**input_data["tool_input"], "file_path": f"/sandbox{path}"},
    }
}

# Modify any tool output (PostToolUse only) — works for built-in and MCP tools
# For built-in tools (Bash, Read, etc.), value must match the tool's output schema
return {
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "updatedToolOutput": {"stdout": "filtered output", "stderr": "", "interrupted": False},
    }
}

# Modify MCP tool output (PostToolUse only) — prefer updatedToolOutput which works for all tools
return {
    "hookSpecificOutput": {
        "hookEventName": input_data["hook_event_name"],
        "updatedMCPToolOutput": {"content": [{"type": "text", "text": "filtered"}]},
    }
}

# Inject context (PreToolUse, PostToolUse, UserPromptSubmit)
return {
    "hookSpecificOutput": {
        "hookEventName": input_data["hook_event_name"],
        "additionalContext": "Extra instructions for Claude",
    }
}

# Decision-based response
return {"decision": "block", "reason": "Not allowed"}

# Stop agent
return {"continue_": False, "stopReason": "Budget exceeded"}
# NOTE: use continue_ (with underscore) — automatically converted to 'continue' for CLI

# Inject system message
return {"systemMessage": "Remember: /etc is protected"}

# Suppress hook output
return {"suppressOutput": True}
```

### Hook Output Types

The SDK exports typed output types for `hookSpecificOutput`:

```python
from claude_agent_sdk import (
    HookJSONOutput,                       # Union: AsyncHookJSONOutput | SyncHookJSONOutput
    NotificationHookSpecificOutput,       # hookEventName, additionalContext
    SubagentStartHookSpecificOutput,      # hookEventName, additionalContext
    PermissionRequestHookSpecificOutput,  # hookEventName, decision (dict)
    PostToolUseFailureHookSpecificOutput, # hookEventName, additionalContext
)
# SyncHookJSONOutput covers: continue_, suppressOutput, stopReason,
#                             decision, systemMessage, reason, hookSpecificOutput
# AsyncHookJSONOutput covers: async_ (True), asyncTimeout (int, optional)
# Both can be imported from claude_agent_sdk.types if needed

# Additional hook-specific output types (not in __all__, import from claude_agent_sdk.types):
from claude_agent_sdk.types import (
    PreToolUseHookSpecificOutput,         # hookEventName, permissionDecision ("allow"|"deny"|"ask"|"defer"), permissionDecisionReason, updatedInput, additionalContext
    PostToolUseHookSpecificOutput,        # hookEventName, additionalContext, updatedToolOutput (all tools), updatedMCPToolOutput (MCP only)
    UserPromptSubmitHookSpecificOutput,   # hookEventName, additionalContext
    SessionStartHookSpecificOutput,       # hookEventName, additionalContext — for future SessionStart event (not yet in HookEvent union)
)
```

### Async Hooks

```python
return {"async_": True, "asyncTimeout": 30000}  # 30s timeout
# NOTE: use async_ (with underscore) — automatically converted to 'async' for CLI
```

### Hook Input Fields

Common fields on all hooks: `session_id`, `transcript_path`, `cwd`, `permission_mode`

| Field | Hooks |
|-------|-------|
| `tool_name`, `tool_input`, `tool_use_id` | PreToolUse, PostToolUse, PostToolUseFailure |
| `tool_name`, `tool_input` | PermissionRequest |
| `tool_response` | PostToolUse |
| `error`, `is_interrupt` | PostToolUseFailure |
| `agent_id` *(optional)*, `agent_type` *(optional)* | PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest — present when hook fires inside a subagent |
| `prompt` | UserPromptSubmit |
| `stop_hook_active` | Stop, SubagentStop |
| `agent_id`, `agent_type` *(required)* | SubagentStart, SubagentStop |
| `agent_transcript_path` | SubagentStop |
| `trigger` (`"manual" \| "auto"`) | PreCompact |
| `custom_instructions` | PreCompact |
| `message`, `title`, `notification_type` | Notification |
| `permission_suggestions` | PermissionRequest |

### Full Hook Example

```python
from claude_agent_sdk import query, ClaudeAgentOptions, HookMatcher, HookContext
from typing import Any

async def validate_bash(
    input_data: dict[str, Any], tool_use_id: str | None, context: HookContext
) -> dict[str, Any]:
    if input_data["tool_name"] == "Bash":
        command = input_data["tool_input"].get("command", "")
        if "rm -rf /" in command:
            return {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": "Dangerous command blocked",
                }
            }
    return {}

async def log_tool_use(
    input_data: dict[str, Any], tool_use_id: str | None, context: HookContext
) -> dict[str, Any]:
    print(f"Tool used: {input_data.get('tool_name')}")
    return {}

options = ClaudeAgentOptions(
    hooks={
        "PreToolUse": [
            HookMatcher(matcher="Bash", hooks=[validate_bash], timeout=120),
            HookMatcher(hooks=[log_tool_use]),
        ],
        "PostToolUse": [
            HookMatcher(hooks=[log_tool_use]),
        ],
    }
)

async for message in query(prompt="Analyze this codebase", options=options):
    print(message)
```

---

## Permissions

### PermissionMode

```python
from typing import Literal

PermissionMode = Literal[
    "default",            # Prompt user for each action
    "acceptEdits",        # Auto-allow file edits, prompt for others
    "plan",               # Read-only planning mode — no writes/execution
    "bypassPermissions",  # Skip all prompts (use with caution)
    "dontAsk",            # Never ask for permission (alias for bypassPermissions in some contexts)
    "auto",               # Delegate permission decisions to the CLI heuristics (added v0.1.57)
]
```

**Note**: The Python SDK exposes 6 permission modes as of v0.1.81 (`dontAsk` added in v0.1.81; `auto` added in v0.1.57). The TypeScript SDK additionally has `"delegate"`.

### `can_use_tool`

> **⚠️ Known Issue**: The `can_use_tool` callback is currently non-functional — callbacks are never invoked by the CLI even when correctly configured. See [KI #27](#27-can_use_tool-callback-never-invoked-issue-469). Use `PreToolUse` hooks instead for permission enforcement.

```python
from claude_agent_sdk.types import PermissionResultAllow, PermissionResultDeny

CanUseTool = Callable[
    [str, dict[str, Any], ToolPermissionContext],
    Awaitable[PermissionResultAllow | PermissionResultDeny]
]
```

#### PermissionResultAllow

```python
@dataclass
class PermissionResultAllow:
    behavior: Literal["allow"] = "allow"
    updated_input: dict[str, Any] | None = None
    updated_permissions: list[PermissionUpdate] | None = None
```

#### PermissionResultDeny

```python
@dataclass
class PermissionResultDeny:
    behavior: Literal["deny"] = "deny"
    message: str = ""
    interrupt: bool = False
```

#### ToolPermissionContext

```python
@dataclass
class ToolPermissionContext:
    signal: Any | None = None            # Reserved for future abort signal
    suggestions: list[PermissionUpdate] = field(default_factory=list)  # Permission suggestions from CLI
    tool_use_id: str | None = None       # Unique ID for this tool call within the assistant message
    agent_id: str | None = None          # Sub-agent ID, if running inside a Task-spawned sub-agent
    blocked_path: str | None = None      # File path that triggered the permission request (if applicable)
    decision_reason: str | None = None   # Why this permission request was triggered (forwarded from PreToolUse hook permissionDecisionReason)
    title: str | None = None             # Full permission prompt sentence (e.g. "Claude wants to read foo.txt") — use as primary prompt text
    display_name: str | None = None      # Short noun phrase for the action (e.g. "Read file") — suitable for button labels
    description: str | None = None       # Human-readable subtitle for the permission UI
```

#### PermissionUpdate

```python
from claude_agent_sdk.types import PermissionUpdate, PermissionRuleValue, PermissionBehavior

PermissionBehavior = Literal["allow", "deny", "ask"]

@dataclass
class PermissionRuleValue:
    tool_name: str
    rule_content: str | None = None

@dataclass
class PermissionUpdate:
    type: Literal["addRules", "replaceRules", "removeRules", "setMode", "addDirectories", "removeDirectories"]
    rules: list[PermissionRuleValue] | None = None
    behavior: PermissionBehavior | None = None
    mode: PermissionMode | None = None
    directories: list[str] | None = None
    destination: Literal["userSettings", "projectSettings", "localSettings", "session"] | None = None

    def to_dict(self) -> dict[str, Any]: ...        # Converts to TypeScript control protocol format (camelCase)
    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "PermissionUpdate": ...  # Inverse of to_dict(); parses wire format
```

#### Example

```python
from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions
from claude_agent_sdk.types import PermissionResultAllow, PermissionResultDeny

async def custom_permission_handler(
    tool_name: str, input_data: dict, context: dict
) -> PermissionResultAllow | PermissionResultDeny:
    # Block writes to system directories
    if tool_name == "Write" and input_data.get("file_path", "").startswith("/system/"):
        return PermissionResultDeny(
            message="System directory write not allowed", interrupt=True
        )

    # Redirect sensitive file operations to sandbox
    if tool_name in ["Write", "Edit"] and "config" in input_data.get("file_path", ""):
        safe_path = f"./sandbox/{input_data['file_path']}"
        return PermissionResultAllow(
            updated_input={**input_data, "file_path": safe_path}
        )

    # Allow everything else
    return PermissionResultAllow(updated_input=input_data)

options = ClaudeAgentOptions(
    can_use_tool=custom_permission_handler,
    allowed_tools=["Read", "Write", "Edit"],
)
```

---

## MCP Servers

### Config Types

```python
from claude_agent_sdk.types import (
    McpStdioServerConfig, McpSSEServerConfig, McpHttpServerConfig, McpSdkServerConfig
)

# stdio (type field optional, defaults to 'stdio')
{"command": "npx", "args": ["@playwright/mcp@latest"], "env": {"KEY": "val"}}

# HTTP (type required)
{"type": "http", "url": "https://api.example.com/mcp", "headers": {"Authorization": "Bearer ..."}}

# SSE (type required)
{"type": "sse", "url": "https://api.example.com/mcp/sse", "headers": {}}

# In-process SDK server (from create_sdk_mcp_server)
{"type": "sdk", "name": "my-server", "instance": mcp_server_instance}
```

**Status-response-only config types** (returned by `get_mcp_status()`, not used for configuration):

```python
from claude_agent_sdk.types import McpSdkServerConfigStatus, McpClaudeAIProxyServerConfig

# SDK server config in status responses (no 'instance' field — not serializable)
class McpSdkServerConfigStatus(TypedDict):
    type: Literal["sdk"]
    name: str

# Claude.ai proxy server (auto-discovered cloud MCP servers)
class McpClaudeAIProxyServerConfig(TypedDict):
    type: Literal["claudeai-proxy"]
    url: str
    id: str
```

**`get_mcp_status()` return types** (from `claude_agent_sdk`):

```python
from claude_agent_sdk import (
    McpStatusResponse, McpServerStatus, McpServerConnectionStatus,
    McpServerInfo, McpToolAnnotations, McpToolInfo,
)

class McpStatusResponse(TypedDict):
    mcpServers: list[McpServerStatus]          # All configured MCP servers and their state

McpServerConnectionStatus = Literal[
    "connected",    # Server is connected and tools are available
    "failed",       # Connection failed (see .error field)
    "needs-auth",   # Server requires authentication
    "pending",      # Connection in progress
    "disabled",     # Server has been toggled off
]

class McpServerInfo(TypedDict):
    name: str       # Server name from MCP initialize handshake
    version: str    # Server version from MCP initialize handshake

class McpToolAnnotations(TypedDict, total=False):
    readOnly: bool      # Tool only reads data, no side effects
    destructive: bool   # Tool may have destructive effects
    openWorld: bool     # Tool may interact with external systems

class McpToolInfo(TypedDict):
    name: str
    description: NotRequired[str]
    annotations: NotRequired[McpToolAnnotations]

class McpServerStatus(TypedDict):
    name: str                                   # Server name as configured
    status: McpServerConnectionStatus           # Current connection status
    serverInfo: NotRequired[McpServerInfo]      # From MCP handshake (available when connected)
    error: NotRequired[str]                     # Error message (available when status is 'failed')
    config: NotRequired[McpServerStatusConfig]  # Server configuration (URL, command, etc.)
    scope: NotRequired[str]                     # Config scope: project, user, local, claudeai, managed
    tools: NotRequired[list[McpToolInfo]]       # Tools provided by server (available when connected)
```

```python
# Example: checking server health and listing tools
status = await client.get_mcp_status()
for server in status["mcpServers"]:
    print(f"{server['name']}: {server['status']}")
    if server["status"] == "failed":
        print(f"  Error: {server.get('error')}")
    elif server["status"] == "connected":
        for tool in server.get("tools", []):
            print(f"  Tool: {tool['name']} — {tool.get('description', '')}")
```

**Tool naming**: `mcp__<server-name>__<tool-name>` (double underscores)

### In-Process MCP Server Example

```python
import asyncio
from claude_agent_sdk import query, tool, create_sdk_mcp_server, ClaudeAgentOptions, ResultMessage
from typing import Any

@tool("get_weather", "Get weather for a city", {"city": str})
async def get_weather(args: dict[str, Any]) -> dict[str, Any]:
    return {"content": [{"type": "text", "text": f"Weather in {args['city']}: 72F, sunny"}]}

server = create_sdk_mcp_server(name="weather", tools=[get_weather])

async def main():
    options = ClaudeAgentOptions(
        mcp_servers={"weather": server},
        allowed_tools=["mcp__weather__get_weather"],
    )
    async for msg in query(prompt="What's the weather in Tokyo?", options=options):
        if isinstance(msg, ResultMessage) and msg.subtype == "success":
            print(msg.result)

asyncio.run(main())
```

### MCP Config from File

The Python SDK can load MCP configs from a file path:

```python
options = ClaudeAgentOptions(
    mcp_servers="/path/to/mcp-config.json"
)
```

### MCP Gotchas

- **URL-based servers require `type` field** — missing it causes opaque "process exited with code 1"
- **In-process SDK MCP servers don't support concurrent queries** — use stdio servers instead
- **Unicode U+2028/U+2029 in tool results breaks JSON** — sanitize all MCP responses

---

## Subagents

### AgentDefinition

```python
@dataclass
class AgentDefinition:
    description: str                                         # When to use
    prompt: str                                              # System prompt
    tools: list[str] | None = None                           # Allowed tools (inherits if omitted)
    disallowedTools: list[str] | None = None                 # Explicitly blocked tools
    model: str | None = None                                 # Model alias ("sonnet","opus","haiku","inherit") or full model ID
    skills: list[str] | None = None                          # Skill names to load (added v0.1.50)
    memory: Literal["user", "project", "local"] | None = None  # Memory setting source (added v0.1.50)
    mcpServers: list[str | dict[str, Any]] | None = None     # MCP servers: name strings or inline configs (added v0.1.50)
    initialPrompt: str | None = None                         # Initial prompt to send when agent starts
    maxTurns: int | None = None                              # Maximum conversation turns for this agent
    background: bool | None = None                           # Run agent in the background (added v0.1.81)
    effort: Literal["low", "medium", "high", "xhigh", "max"] | int | None = None  # Effort level for thinking depth (added v0.1.81; "xhigh" = extended depth on Opus 4.7+)
    permissionMode: PermissionMode | None = None             # Permission mode for this agent (added v0.1.81)
```

Include `Task` in parent's `allowed_tools` — subagents are invoked via the Task tool.

```python
from claude_agent_sdk import query, ClaudeAgentOptions

options = ClaudeAgentOptions(
    allowed_tools=["Read", "Glob", "Grep", "Task"],
    agents={
        "reviewer": AgentDefinition(
            description="Code review specialist",
            prompt="Review code for bugs and best practices.",
            tools=["Read", "Glob", "Grep"],
            model="haiku",
        )
    },
)

async for msg in query(prompt="Use the reviewer to check this code", options=options):
    print(msg)
```

### Tool Enforcement Warning

**`AgentDefinition.tools` is NOT enforced at the API level** — subagents can call tools they should not have access to, potentially causing infinite recursion. Use `can_use_tool` callback to block disallowed tools in subagents (same workaround as TypeScript SDK).

---

## Extended Thinking

Control Claude's extended thinking behavior with the `thinking` and `effort` options.

### ThinkingConfig Types

```python
from claude_agent_sdk.types import ThinkingConfig, ThinkingDisplay

# Controls whether thinking text is returned summarized or omitted (added v0.1.81).
# Opus 4.7+ defaults to "omitted" (signature-only); pass "summarized" to receive text.
ThinkingDisplay = Literal["summarized", "omitted"]

# Adaptive mode - Claude decides when to think
ThinkingConfigAdaptive = {"type": "adaptive", "display": ThinkingDisplay}   # display optional

# Enabled mode - budget-limited thinking
ThinkingConfigEnabled = {"type": "enabled", "budget_tokens": int, "display": ThinkingDisplay}  # display optional

# Disabled mode - no thinking blocks
ThinkingConfigDisabled = {"type": "disabled"}
```

### Examples

```python
from claude_agent_sdk import query, ClaudeAgentOptions

# Adaptive thinking (recommended)
options = ClaudeAgentOptions(
    thinking={"type": "adaptive"},
    effort="high"
)

# Budget-limited thinking
options = ClaudeAgentOptions(
    thinking={"type": "enabled", "budget_tokens": 10000},
    effort="medium"
)

# Disabled thinking
options = ClaudeAgentOptions(
    thinking={"type": "disabled"}
)

async for msg in query(prompt="Solve this complex problem", options=options):
    print(msg)
```

**Note**: `thinking` takes precedence over the deprecated `max_thinking_tokens` option.

---

## Structured Outputs

Define a JSON Schema and get validated data in `message.structured_output`.

```python
import asyncio
from claude_agent_sdk import query, ClaudeAgentOptions, ResultMessage

schema = {
    "type": "object",
    "properties": {
        "summary": {"type": "string"},
        "sentiment": {"type": "string", "enum": ["positive", "neutral", "negative"]},
        "confidence": {"type": "number"},
    },
    "required": ["summary", "sentiment", "confidence"],
}

async def main():
    options = ClaudeAgentOptions(
        output_format={"type": "json_schema", "schema": schema}
    )
    async for msg in query(prompt="Analyze this feedback", options=options):
        if isinstance(msg, ResultMessage) and msg.subtype == "success":
            if msg.structured_output:
                print(msg.structured_output)

asyncio.run(main())
```

Error subtype `error_max_structured_output_retries` indicates validation failures after retries.

### With Pydantic

```python
from pydantic import BaseModel

class Analysis(BaseModel):
    summary: str
    sentiment: str
    confidence: float

schema = Analysis.model_json_schema()

options = ClaudeAgentOptions(
    output_format={"type": "json_schema", "schema": schema}
)

async for msg in query(prompt="Analyze this", options=options):
    if isinstance(msg, ResultMessage) and msg.subtype == "success" and msg.structured_output:
        parsed = Analysis.model_validate(msg.structured_output)
        print(parsed.summary, parsed.sentiment, parsed.confidence)
```

---

## Sandbox

```python
from claude_agent_sdk.types import SandboxSettings, SandboxNetworkConfig

# TypedDict with all fields optional
class SandboxSettings(TypedDict, total=False):
    enabled: bool                              # Enable sandbox mode
    autoAllowBashIfSandboxed: bool             # Auto-approve bash when sandboxed
    excludedCommands: list[str]                # Always bypass sandbox (static allowlist)
    allowUnsandboxedCommands: bool             # Model can request unsandboxed execution
    network: SandboxNetworkConfig
    ignoreViolations: SandboxIgnoreViolations
    enableWeakerNestedSandbox: bool

class SandboxNetworkConfig(TypedDict, total=False):
    allowedDomains: list[str]                  # Domain names sandboxed processes can access
    deniedDomains: list[str]                   # Domains always blocked (even if matched by allowedDomains)
    allowManagedDomainsOnly: bool              # When True in managed settings, only managed allowedDomains respected
    allowUnixSockets: list[str]                # Specific Unix socket paths (e.g., SSH agents)
    allowAllUnixSockets: bool                  # Allow all Unix sockets (less secure)
    allowLocalBinding: bool                    # Allow binding to localhost ports (macOS only)
    allowMachLookup: list[str]                 # macOS only: XPC/Mach service names (supports trailing wildcard)
    httpProxyPort: int                         # HTTP proxy port if bringing your own proxy
    socksProxyPort: int                        # SOCKS5 proxy port if bringing your own proxy

class SandboxIgnoreViolations(TypedDict, total=False):
    file: list[str]                            # File path patterns to ignore
    network: list[str]                         # Network patterns to ignore
```

`excludedCommands` = static allowlist (model has no control).
`allowUnsandboxedCommands` = model can set `dangerouslyDisableSandbox: True` in Bash input, which falls back to `can_use_tool` for approval.

### Example

```python
from claude_agent_sdk import query, ClaudeAgentOptions

sandbox_settings = {
    "enabled": True,
    "autoAllowBashIfSandboxed": True,
    "network": {"allowLocalBinding": True},
}

async for message in query(
    prompt="Build and test my project",
    options=ClaudeAgentOptions(sandbox=sandbox_settings),
):
    print(message)
```

**Warning**: If `permission_mode="bypassPermissions"` and `allowUnsandboxedCommands=True`, the model can autonomously execute commands outside the sandbox without any approval. This combination effectively allows the model to escape sandbox isolation.

---

## Sessions

```python
import asyncio
from claude_agent_sdk import query, ClaudeAgentOptions, SystemMessage, ResultMessage

# Capture session ID
session_id = None
async for msg in query(prompt="Read auth module"):
    if isinstance(msg, SystemMessage) and msg.subtype == "init":
        session_id = msg.data.get("session_id")

# Resume
async for msg in query(
    prompt="Now find callers",
    options=ClaudeAgentOptions(resume=session_id),
):
    pass

# Fork (creates new branch, original unchanged)
async for msg in query(
    prompt="Try GraphQL instead",
    options=ClaudeAgentOptions(resume=session_id, fork_session=True),
):
    pass

# Continue most recent conversation
async for msg in query(
    prompt="Continue where we left off",
    options=ClaudeAgentOptions(continue_conversation=True),
):
    pass
```

**Session tips:**
- Use `max_turns` as a safety net — sessions never timeout on their own
- Use `max_budget_usd` to limit costs per session
- Fork proactively before context gets too large
- `ClaudeSDKClient` naturally maintains sessions across multiple `query()` calls

### File Checkpointing

Requires `enable_file_checkpointing=True`. Available on `ClaudeSDKClient` only.

To rewind to a specific user message you must also capture the `UserMessage.uuid`. Pass `extra_args={"replay-user-messages": None}` so that `UserMessage` objects with a populated `uuid` field are emitted in the response stream.

```python
from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions, UserMessage

options = ClaudeAgentOptions(
    enable_file_checkpointing=True,
    extra_args={"replay-user-messages": None},  # Required to get UserMessage.uuid
)
async with ClaudeSDKClient(options) as client:
    checkpoint_id = None
    await client.query("Refactor auth module")
    async for msg in client.receive_response():
        if isinstance(msg, UserMessage) and msg.uuid:
            checkpoint_id = msg.uuid  # Save for later rewind

    # Rewind files to their state at that user message
    if checkpoint_id:
        await client.rewind_files(checkpoint_id)
```

### Listing & Reading Sessions

Use `list_sessions()`, `get_session_info()`, and `get_session_messages()` to browse historical session metadata and read transcripts without running a new query. All functions are synchronous and read directly from `~/.claude/projects/`.

```python
from claude_agent_sdk import list_sessions, get_session_info, get_session_messages, list_subagents, get_subagent_messages, SDKSessionInfo, SessionMessage

# List sessions for a specific project directory
sessions: list[SDKSessionInfo] = list_sessions(
    directory="/path/to/project",  # omit to list all projects
    limit=20,                      # optional cap
    offset=0,                      # skip N sessions from start (default 0)
    include_worktrees=True,        # include git worktree paths (default True)
)

for s in sessions:
    print(s.session_id, s.summary, s.last_modified)
    # SDKSessionInfo fields:
    # .session_id     str           — UUID
    # .summary        str           — auto title, custom title, or first prompt
    # .last_modified  int           — milliseconds since epoch
    # .file_size      int | None    — bytes (None for remote storage)
    # .custom_title   str | None    — user-set via /rename
    # .first_prompt   str | None    — first meaningful user prompt
    # .git_branch     str | None    — git branch at end of session
    # .cwd            str | None    — working directory
    # .tag            str | None    — user-set session tag
    # .created_at     int | None    — creation time in ms since epoch

# Look up a single session by ID (no directory scan)
info: SDKSessionInfo | None = get_session_info(
    session_id="550e8400-e29b-41d4-a716-446655440000",
    directory="/path/to/project",  # optional
)
if info:
    print(info.summary, info.custom_title)

# Read all messages from a session transcript
messages: list[SessionMessage] = get_session_messages(
    session_id="550e8400-e29b-41d4-a716-446655440000",
    directory="/path/to/project",  # optional; searches all projects if omitted
    limit=50,                      # optional pagination
    offset=0,                      # skip N messages from start
)

for msg in messages:
    print(msg.type, msg.message)
    # SessionMessage fields:
    # .type              "user" | "assistant"
    # .uuid              str     — unique message identifier
    # .session_id        str     — session this message belongs to
    # .message           Any     — raw Anthropic API message dict (role, content)
    # .parent_tool_use_id  None  — always None (tool-use sidechain messages filtered out)
```

> **Note**: `list_sessions()` uses only `stat` + head/tail reads — no full JSONL parsing — so it is fast even for large session files.

### Listing Subagents & Reading Subagent Transcripts

Use `list_subagents()` and `get_subagent_messages()` to read the transcripts of subagents that ran inside a parent session. Subagent transcripts are stored at `~/.claude/projects/<project>/<sessionId>/subagents/agent-<agentId>.jsonl`.

```python
from claude_agent_sdk import list_subagents, get_subagent_messages, SessionMessage

# List all subagent IDs that ran in a session
agent_ids: list[str] = list_subagents(
    session_id="550e8400-e29b-41d4-a716-446655440000",
    directory="/path/to/project",  # optional; searches all projects if omitted
)
print(agent_ids)  # e.g. ["abc123", "def456"]

# Read messages from a specific subagent's transcript
messages: list[SessionMessage] = get_subagent_messages(
    session_id="550e8400-e29b-41d4-a716-446655440000",
    agent_id="abc123",
    directory="/path/to/project",  # optional
    limit=50,                       # optional pagination
    offset=0,
)
for msg in messages:
    print(msg.type, msg.message)
    # SessionMessage fields:
    # .type              "user" | "assistant"
    # .uuid              str     — unique message identifier
    # .session_id        str     — session this message belongs to
    # .message           Any     — raw Anthropic API message dict (role, content)
    # .parent_tool_use_id  None  — always None (tool-use sidechain messages filtered out)
```

**Signatures**:

```python
def list_subagents(
    session_id: str,
    directory: str | None = None,
) -> list[str]:
    """Returns subagent ID strings for all subagents in the session.
    Returns [] if session not found, session_id is not a valid UUID, or no subagents exist."""

def get_subagent_messages(
    session_id: str,
    agent_id: str,
    directory: str | None = None,
    limit: int | None = None,
    offset: int = 0,
) -> list[SessionMessage]:
    """Returns user/assistant messages from a subagent transcript in chronological order.
    Returns [] if session or subagent not found, or the transcript has no visible messages."""
```

> **Note**: Subagent transcripts may be nested in subdirectories such as `subagents/workflows/<runId>/`. Both functions handle nested paths automatically.

### Session Mutations

Use `rename_session()` and `tag_session()` to annotate historical sessions without running a new query. Both functions are synchronous and write directly to the session's JSONL file.

```python
from claude_agent_sdk import rename_session, tag_session

# Rename a session (sets custom title; last write wins)
rename_session(
    session_id="550e8400-e29b-41d4-a716-446655440000",
    title="My refactoring session",
    directory="/path/to/project",  # optional; searches all projects if omitted
)

# Tag a session for filtering (last write wins)
tag_session(
    session_id="550e8400-e29b-41d4-a716-446655440000",
    tag="experiment",
    directory="/path/to/project",
)

# Clear a tag
tag_session(session_id, None)
```

**Signatures**:

```python
def rename_session(session_id: str, title: str, directory: str | None = None) -> None:
    """Raises ValueError (invalid UUID or empty title), FileNotFoundError (session not found)."""

def tag_session(session_id: str, tag: str | None, directory: str | None = None) -> None:
    """Pass None to clear the tag. Raises ValueError, FileNotFoundError."""

def delete_session(session_id: str, directory: str | None = None) -> None:
    """Hard-delete a session by removing its JSONL file.
    Raises ValueError (invalid UUID), FileNotFoundError (session not found).
    For soft-delete, use tag_session(id, '__hidden') and filter on listing."""

def fork_session(
    session_id: str,
    directory: str | None = None,
    up_to_message_id: str | None = None,
    title: str | None = None,
) -> ForkSessionResult:
    """Fork a session into a new branch with fresh UUIDs. Returns ForkSessionResult.
    up_to_message_id: Slice at a specific message (inclusive). Omit to copy full transcript.
    title: Custom title for the fork; derived automatically if omitted.
    Raises ValueError (invalid UUID, no messages, message not found), FileNotFoundError."""
```

**`ForkSessionResult`**:

```python
from claude_agent_sdk import fork_session, delete_session, ForkSessionResult

# Fork an entire session
result: ForkSessionResult = fork_session("550e8400-e29b-41d4-a716-446655440000")
print(result.session_id)  # UUID of the new forked session

# Fork from a specific message (branch at a point in history)
result = fork_session(
    "550e8400-e29b-41d4-a716-446655440000",
    up_to_message_id="660e8400-e29b-41d4-a716-446655440001",
    title="Experiment branch",
)

# Delete a session
delete_session("550e8400-e29b-41d4-a716-446655440000")
```

> **Note**: Tags are Unicode-sanitized (removes zero-width chars, directional marks, private-use characters). Repeated calls are safe — `list_sessions()` reads the last entry.

### Session Store

Mirror session transcripts to external storage (S3, Redis, Postgres, etc.) and resume sessions from the store when the local file is absent. Set `session_store` on `ClaudeAgentOptions` to activate.

#### `SessionStore` Protocol

```python
from claude_agent_sdk import SessionStore, SessionKey, SessionStoreEntry, SessionStoreListEntry, SessionListSubkeysKey

class SessionStore(Protocol):
    # REQUIRED — implement both to get mirroring + resume
    async def append(self, key: SessionKey, entries: list[SessionStoreEntry]) -> None:
        """Called after every local write (~100ms cadence). Failed batches are retried (3 attempts total)
        with short backoff before being dropped and surfaced as a MirrorErrorMessage.
        Timeouts are not retried (in-flight call may still land). Implement as an idempotent upsert."""
        ...

    async def load(self, key: SessionKey) -> list[SessionStoreEntry] | None:
        """Called once before subprocess spawn for resume. Return None for unknown keys."""
        ...

    # OPTIONAL — implement as needed
    async def list_sessions(self, project_key: str) -> list[SessionStoreListEntry]: ...
    async def list_session_summaries(self, project_key: str) -> list[SessionSummaryEntry]: ...
    """Faster alternative to list_sessions() — returns incrementally-maintained summaries
    maintained inside append() via fold_session_summary(). If unimplemented,
    list_sessions_from_store() falls back to list_sessions() + per-session load()."""
    async def delete(self, key: SessionKey) -> None: ...
    async def list_subkeys(self, key: SessionListSubkeysKey) -> list[str]: ...
```

#### Supporting Types

```python
class SessionKey(TypedDict):
    project_key: str     # Scope (default: sanitized cwd). Set to tenant/project ID for multi-tenant apps.
    session_id: str
    subpath: NotRequired[str]  # Omit for main transcript; set for subagent files (e.g. "subagents/agent-<id>")

class SessionStoreEntry(TypedDict, total=False):
    type: Required[str]  # CLI transcript entry type
    uuid: str
    timestamp: str
    # Additional fields are opaque — pass through as-is

class SessionStoreListEntry(TypedDict):
    session_id: str
    mtime: int   # Last-modified time in Unix epoch milliseconds

class SessionSummaryEntry(TypedDict):
    session_id: str
    mtime: int           # Storage write time in Unix epoch ms (same clock as SessionStoreListEntry.mtime)
    data: dict[str, Any] # Opaque SDK-owned summary state — stores MUST NOT interpret; persist verbatim

class SessionListSubkeysKey(TypedDict):
    project_key: str
    session_id: str

SessionStoreFlushMode = Literal["batched", "eager"]
# "batched" (default): buffer entries and flush once per turn (on the result message)
# or when the pending buffer exceeds 500 entries / 1 MiB.
# "eager": trigger a background flush after every transcript_mirror frame so
# SessionStore.append() sees entries in near real time. A slow adapter will not stall
# message streaming; appends are serialized in enqueue order.
```

#### `InMemorySessionStore`

A built-in in-memory adapter useful for testing and short-lived sessions:

```python
from claude_agent_sdk import InMemorySessionStore, ClaudeAgentOptions

store = InMemorySessionStore()  # Stores all transcripts in memory
options = ClaudeAgentOptions(session_store=store)
```

#### `project_key_for_directory`

```python
from claude_agent_sdk import project_key_for_directory

key = project_key_for_directory("/home/user/myproject")
# Returns a sanitized, stable string for use as SessionKey.project_key
# Useful for low-level store operations that work directly with SessionKey
# (the high-level *_from_store / *_via_store functions use directory= instead)
```

#### `fold_session_summary`

Helper for stores that implement `list_session_summaries()`. Call inside `SessionStore.append()` to incrementally maintain summaries without full JSONL re-reads. The `data` field is opaque — stores persist it verbatim and return it in `list_session_summaries()`.

**Signature**: `fold_session_summary(prev, key, entries) -> SessionSummaryEntry`
- `prev` — previous `SessionSummaryEntry` for this key, or `None` for the first append
- `key` — `SessionKey` for the session being folded (do NOT call for subpath keys)
- `entries` — the new batch of `SessionStoreEntry` objects from this `append()` call

```python
from claude_agent_sdk import fold_session_summary, SessionSummaryEntry
from typing import Any

class MyStore:
    async def append(self, key, entries):
        # ... persist entries ...
        # Update summary sidecar (only for main transcripts, not subagent subpaths)
        if "subpath" not in key:
            prev: SessionSummaryEntry | None = await self._load_summary(key)
            new_summary = fold_session_summary(prev, key, entries)
            await self._save_summary(key, new_summary)
```

#### `import_session_to_store`

Replay a local on-disk session (and its subagent transcripts) into a `SessionStore`. Use this to migrate existing local sessions to a remote store, or to catch a store up after a `MirrorErrorMessage` indicated a live-mirror gap. Adapters should treat `entry["uuid"]` as an idempotency key so re-import is duplicate-safe.

```python
from claude_agent_sdk import import_session_to_store

async def import_session_to_store(
    session_id: str,
    store: SessionStore,
    *,
    directory: str | None = None,   # Project directory (searches all if omitted)
    include_subagents: bool = True, # Also import subagent transcripts (default True)
    batch_size: int = 500,          # Max entries per store.append() call
) -> None:
    """Raises ValueError (invalid UUID), FileNotFoundError (session not found)."""
```

```python
# Example: migrate a local session to a remote store
store = MyRemoteStore(...)
await import_session_to_store(
    session_id="550e8400-e29b-41d4-a716-446655440000",
    store=store,
    directory="/path/to/project",
)
# Now resume from the store
async for msg in query(
    prompt="Continue where we left off",
    options=ClaudeAgentOptions(session_store=store, resume="550e8400-e29b-41d4-a716-446655440000"),
):
    ...
```

The imported session's `project_key` matches the on-disk project directory name, so it is resumable via the same `cwd` that originally produced it.

#### Store-Backed Read Functions

Async variants of the session listing/reading functions that use a `SessionStore` adapter instead of local disk:

```python
from claude_agent_sdk import (
    list_sessions_from_store,
    get_session_info_from_store,
    get_session_messages_from_store,
    list_subagents_from_store,
    get_subagent_messages_from_store,
)

# directory is optional — omit to search all projects in CLAUDE_CONFIG_DIR
sessions = await list_sessions_from_store(store, directory="/path/to/project")
info = await get_session_info_from_store(store, session_id="<uuid>", directory="/path/to/project")
messages = await get_session_messages_from_store(store, session_id="<uuid>", directory="/path/to/project")
agent_ids = await list_subagents_from_store(store, session_id="<uuid>", directory="/path/to/project")
sub_msgs = await get_subagent_messages_from_store(store, session_id="<uuid>", agent_id="<id>", directory="/path/to/project")
```

**Signatures**:
```python
async def list_sessions_from_store(session_store, directory=None, limit=None, offset=0) -> list[SDKSessionInfo]
async def get_session_info_from_store(session_store, session_id, directory=None) -> SDKSessionInfo | None
async def get_session_messages_from_store(session_store, session_id, directory=None, limit=None, offset=0) -> list[SessionMessage]
async def list_subagents_from_store(session_store, session_id, directory=None) -> list[str]
async def get_subagent_messages_from_store(session_store, session_id, agent_id, directory=None, limit=None, offset=0) -> list[SessionMessage]
```

#### Store-Backed Mutation Functions

```python
from claude_agent_sdk import (
    rename_session_via_store,
    tag_session_via_store,
    delete_session_via_store,
    fork_session_via_store,
)

await rename_session_via_store(store, session_id="<uuid>", title="New title", directory="/path/to/project")
await tag_session_via_store(store, session_id="<uuid>", tag="experiment", directory="/path/to/project")
await delete_session_via_store(store, session_id="<uuid>", directory="/path/to/project")
result = await fork_session_via_store(store, session_id="<uuid>", directory="/path/to/project")
```

#### Full Example

```python
import asyncio
from claude_agent_sdk import (
    InMemorySessionStore, query, ClaudeAgentOptions,
    ResultMessage, SystemMessage,
)

async def main():
    store = InMemorySessionStore()

    # First session — stored automatically
    session_id = None
    async for msg in query(
        prompt="Analyze this codebase",
        options=ClaudeAgentOptions(
            session_store=store,
            cwd="/my/project",
        ),
    ):
        if isinstance(msg, SystemMessage) and msg.subtype == "init":
            session_id = msg.data.get("session_id")

    # Resume from store (even if local file is absent)
    if session_id:
        async for msg in query(
            prompt="Now implement the changes",
            options=ClaudeAgentOptions(
                session_store=store,
                resume=session_id,
                cwd="/my/project",
            ),
        ):
            if isinstance(msg, ResultMessage) and msg.subtype == "success":
                print(msg.result)

asyncio.run(main())
```

**Notes**:
- The subprocess still writes to local disk; the adapter receives a secondary copy
- `session_store_flush` controls delivery cadence — use `"eager"` for near-real-time delivery at the cost of more adapter calls; default `"batched"` is lower overhead (flushes once per turn or when buffer exceeds 500 entries / 1 MiB)
- `load_timeout_ms` (default 60 000) prevents a slow store from blocking subprocess spawn
- Deletion of a main-transcript key should cascade to all subkeys in the adapter
- Use `project_key_for_directory(cwd)` to match the key the CLI uses automatically

#### Testing Your `SessionStore` Adapter

The `claude_agent_sdk.testing` subpackage provides a shared conformance suite for `SessionStore` adapters. Use it to verify your implementation satisfies all 14 behavioral contracts required by the SDK (added v0.1.81).

```python
from claude_agent_sdk.testing import run_session_store_conformance

# Works with any test runner (pytest, unittest, etc.):

import pytest

@pytest.mark.asyncio
async def test_my_store_conformance():
    await run_session_store_conformance(MyRedisStore)
    # Optionally skip optional methods you haven't implemented:
    await run_session_store_conformance(
        MyWORMStore,
        skip_optional=frozenset({"delete", "list_subkeys"}),
    )
```

**Signature**:

```python
async def run_session_store_conformance(
    make_store: Callable[[], SessionStore | Awaitable[SessionStore]],
    *,
    skip_optional: frozenset[str] = frozenset(),
) -> None:
    """Assert the 14 SessionStore behavioral contracts.

    make_store: Invoked once per contract for isolation. May be sync or async.
    skip_optional: Names of optional methods to skip
        ("list_sessions", "list_session_summaries", "delete", "list_subkeys").
        Contracts for optional methods are also skipped automatically when the
        store does not override the method.
    """
```

The suite validates: append+load round-trips, subpath isolation, project_key isolation, `list_sessions()`, `list_session_summaries()` staleness ordering, `delete()` cascade, `list_subkeys()`, and sidecar fold idempotency. Does not require pytest — assertions use plain `assert`.

---

## Debugging & Error Handling

### Error Types

```python
from claude_agent_sdk import (
    ClaudeSDKError,         # Base exception
    CLINotFoundError,       # Claude Code CLI not installed
    CLIConnectionError,     # Connection to Claude Code failed
    ProcessError,           # Process failed (has exit_code, stderr)
    CLIJSONDecodeError,     # JSON parsing failed (has line, original_error)
)
```

### Error Handling Pattern

```python
from claude_agent_sdk import query, CLINotFoundError, ProcessError, CLIJSONDecodeError

try:
    async for message in query(prompt="Hello"):
        print(message)
except CLINotFoundError:
    print("Install Claude Code: npm install -g @anthropic-ai/claude-code")
except ProcessError as e:
    print(f"Process failed: exit_code={e.exit_code}, stderr={e.stderr}")
except CLIJSONDecodeError as e:
    print(f"JSON parse error on line: {e.line}")
except ClaudeSDKError as e:
    print(f"SDK error: {e}")
```

### stderr Callback

```python
import logging

logger = logging.getLogger("claude-sdk")

options = ClaudeAgentOptions(
    stderr=lambda data: logger.debug(f"CLI stderr: {data}")
)
```

### Diagnostic Checklist for "process exited with code 1"

1. **Missing `type` field on URL-based MCP config** — add `type: "http"` or `type: "sse"`
2. **Invalid model ID** — verify model string (e.g., `claude-sonnet-4-5-20250929`, not `claude-3.5-sonnet`)
3. **CLI not installed** — run `npm install -g @anthropic-ai/claude-code`
4. **`ANTHROPIC_LOG=debug` set in env** — remove it; it corrupts the JSON protocol
5. **Custom `cli_path` pointing to wrong binary** — verify path exists and is executable

### Cost Monitoring

```python
async for msg in query(
    prompt="Analyze codebase",
    options=ClaudeAgentOptions(max_budget_usd=5.00),
):
    if isinstance(msg, ResultMessage) and msg.subtype == "success":
        print(f"Cost: ${msg.total_cost_usd}")
        print(f"Turns: {msg.num_turns}")
        print(f"Duration: {msg.duration_ms}ms (API: {msg.duration_api_ms}ms)")
        if msg.usage:
            for model, usage in msg.usage.items():
                print(f"  {model}: {usage}")
```

---

## Known Issues

<!-- This section is populated by the research agent. -->
<!-- Add confirmed, reproducible issues with workarounds below. -->

### #1: Hook Callback Errors in bypassPermissions Mode
**Error**: `Error in hook callback hook_0: Stream closed` followed by ~50 lines of minified CLI source ([#554](https://github.com/anthropics/claude-agent-sdk-python/issues/554))
**Cause**: Since v0.1.29, new hook events (`SubagentStop`, `Notification`, `PermissionRequest`) attempt to communicate over a closed stream when operating in `bypassPermissions` mode.
**Fix**: Downgrade to v0.1.28 (CLI v2.1.30) or wait for fix. The errors are cosmetic—tools execute successfully despite the noise.

### #2: `allowed_tools` Is a Permission Allowlist, Not a Tool Restriction
**Error**: Passing `allowed_tools=[]` to disable all tools fails silently; all tools remain available instead ([#523](https://github.com/anthropics/claude-agent-sdk-python/issues/523), [#634](https://github.com/anthropics/claude-agent-sdk-python/issues/634))
**Cause**: `allowed_tools` maps to `--allowedTools` (a permission pre-approval list), NOT to `--tools` (tool availability). Additionally, empty lists are falsy, so `allowed_tools=[]` omits the flag entirely. These are two distinct options:
- `tools` — controls **which tools are available** (maps to `--tools`)
- `allowed_tools` — controls **which tools are pre-approved** for permission prompts (maps to `--allowedTools`)
**Fix**: Use `tools=[]` to disable all tools, or `tools=["Read", "Grep"]` to restrict to specific tools. `allowed_tools` should only be used to pre-approve specific tools in a broader permission workflow.
```python
# WRONG — allowed_tools is for permission pre-approval, not tool restriction
options = ClaudeAgentOptions(allowed_tools=[])  # Does nothing

# CORRECT — use tools= to control tool availability
options = ClaudeAgentOptions(tools=[])               # Disables all tools
options = ClaudeAgentOptions(tools=["Read", "Grep"])  # Only these tools
```

### #3: Sub-agents Not Registered When Command Exceeds 100k Chars (Fixed in v0.1.35)
**Error**: Custom agents silently fail to register when CLI command string exceeds Linux's 100k character limit ([#567](https://github.com/anthropics/claude-agent-sdk-python/issues/567))
**Cause**: SDK writes agents to temp file (`@/tmp/xxx.json`) but CLI didn't support `@filepath` syntax, attempting to parse it as JSON directly.
**Fix**: Fixed in v0.1.35. If using older versions, reduce system prompt size, use fewer/smaller agents, or upgrade.

### #4: StructuredOutput Validation Fails When Agent Wraps Output
**Error**: `Output does not match required schema: root: must have required property 'X'` followed by `error_max_structured_output_retries` ([#571](https://github.com/anthropics/claude-agent-sdk-python/issues/571))
**Cause**: Agent non-deterministically wraps JSON in `{"output": {...}}` instead of providing schema directly, breaking root-level validation.
**Fix**: Add explicit prompt instruction:
```python
system_prompt = "**CRITICAL**: When using StructuredOutput tool, provide the JSON object directly - do NOT wrap in {\"output\": {...}}"
```
Note: This workaround is fragile due to agent non-determinism. Prefer using `output_format` option instead of relying on agent to call StructuredOutput tool.

### #5: `cwd` Option Ignored or Overridden
**Error**: Setting `cwd="/path/to/app"` is ignored; Claude uses random paths or symlink-resolved paths like `/private/path/to/app` ([#10](https://github.com/anthropics/claude-agent-sdk-python/issues/10))
**Cause**: Combination of macOS symlink resolution, Claude's path heuristics, and potential model-specific behavior.
**Workaround**: Explicitly specify the working directory in your prompt: `"Work in /path/to/app directory"`. Some users report this works correctly with Opus but not Sonnet. Monitor `SystemMessage` init data for actual `cwd` value.

### #6: Query.close() Hangs Indefinitely with 100% CPU
**Error**: Calling `client.disconnect()` or context manager exit hangs forever, consuming 100% CPU in `anyio._deliver_cancellation()` ([#378](https://github.com/anthropics/claude-agent-sdk-python/issues/378))
**Cause**: No timeout on `Query.close()` task group cleanup. If tasks don't respond to cancellation (e.g., subprocess killed by OOM), anyio spins forever trying to deliver cancellation.
**Workaround**: Wrap disconnect in asyncio timeout:
```python
async with asyncio.timeout(10):
    await client.disconnect()
```
Or set `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT=10000` (milliseconds) environment variable.

### #7: FastAPI/Uvicorn Context Issue - Only Init Message Returned
**Error**: SDK query works in tests but fails in FastAPI handlers; only `SystemMessage(subtype="init")` is returned, no assistant response ([#462](https://github.com/anthropics/claude-agent-sdk-python/issues/462))
**Cause**: Asyncio event loop context mismatch between FastAPI and SDK subprocess transport.
**Workaround**: Unknown. Issue has 5 reactions but no confirmed fix yet. May be related to anyio task group context isolation.

### #8: PreToolUse Hooks Not Called When File Doesn't Exist
**Error**: PreToolUse hooks are skipped when `Read` tool is called with a non-existent file path ([#316](https://github.com/anthropics/claude-agent-sdk-python/issues/316))
**Cause**: File existence validation happens before hook invocation, contradicting documentation.
**Impact**: Breaks path translation hooks that need to modify file paths before validation.
**Workaround**: None. Avoid relying on PreToolUse hooks for Read path modification.

### #9: Thinking Blocks Missing with Opus 4.6 (Fixed in v0.1.36)
**Error**: No thinking blocks returned when using `claude-opus-4-6` with `max_thinking_tokens` ([#553](https://github.com/anthropics/claude-agent-sdk-python/issues/553))
**Cause**: Opus 4.6 deprecated `budget_tokens` in favor of adaptive thinking.
**Fix**: Use `thinking={"type": "adaptive"}` and `effort="high"` instead of `max_thinking_tokens`. Fixed in v0.1.36 with addition of `thinking` and `effort` options.

### #10: SDK Usage Blocked Inside Claude Code Sessions (Hooks/Plugins)
**Error**: `Error: Claude Code cannot be launched inside another Claude Code session.` when using SDK from hooks, plugins, or subagents ([#573](https://github.com/anthropics/claude-agent-sdk-python/issues/573))
**Cause**: Subprocess inherits `CLAUDECODE=1` environment variable from parent Claude Code process. The spawned CLI detects this and refuses to start.
**Fix** (v0.1.81): `CLAUDECODE` is now automatically filtered from the subprocess environment (PR [#732](https://github.com/anthropics/claude-agent-sdk-python/issues/732)). Upgrade to v0.1.81+ to resolve. On v0.1.50, override manually:
```python
options = ClaudeAgentOptions(
    env={"CLAUDECODE": ""},
    # ... other options
)
```

### #11: Unsupported Content Block Types Silently Dropped in SDK MCP Tools
**Error**: Custom MCP tools returning certain content block types (e.g., `search_result`, `audio`) have those blocks silently dropped before reaching Claude ([#574](https://github.com/anthropics/claude-agent-sdk-python/issues/574), [#292](https://github.com/anthropics/claude-agent-sdk-python/issues/292))
**Cause**: The SDK's `create_sdk_mcp_server()` handler originally only recognized `text` and `image` content types; all other types fell through and were discarded.
**Fix** (v0.1.81): `resource_link`, `embedded_resource`, and `audio` content types are now handled (PR [#725](https://github.com/anthropics/claude-agent-sdk-python/issues/725)). The `search_result` type remains unsupported.
**Impact on search_result**: Cannot use [native citations](https://platform.claude.com/docs/en/build-with-claude/search-results) with custom RAG tools in the Agent SDK.
**Workaround**: For `search_result` blocks, bypass SDK and use `anthropic.AsyncAnthropic` directly for RAG workflows requiring citations.

### #12: Session Forking Fails with ClaudeSDKClient Since v0.1.28
**Error**: `ProcessError: Command failed with exit code 1` when calling `ClaudeSDKClient` with `resume=session_id, fork_session=True` ([#575](https://github.com/anthropics/claude-agent-sdk-python/issues/575))
**Cause**: Regression introduced in v0.1.28 affecting fork workflow when MCP servers are configured.
**Workaround**: Downgrade to v0.1.27, or avoid forking with MCP servers until fixed.

### #13: ClaudeSDKClient Hangs in FastAPI/Starlette (ASGI Frameworks)
**Error**: `ClaudeSDKClient` hangs silently on second `receive_response()` when reused across different ASGI request tasks. No error raised—messages never arrive ([#576](https://github.com/anthropics/claude-agent-sdk-python/issues/576))
**Cause**: SDK's internal anyio task group (created during `connect()`) cannot deliver messages across asyncio task boundaries. FastAPI handles each HTTP request in a separate task.
**Impact**: SDK cannot be used for multi-turn conversations in web servers without workaround.
**Workaround**: Create a dedicated `asyncio.Task` per session that owns the SDK client, with `asyncio.Queue` bridges to HTTP handlers:
```python
class SessionWorker:
    async def _run(self):
        client = ClaudeSDKClient(options=...)
        await client.connect()  # Task W
        while True:
            message, out_q = await self._input.get()
            await client.query(message)  # Task W
            async for msg in client.receive_response():  # Task W
                await out_q.put(msg)

    async def query_and_stream(self, message):
        out_q = asyncio.Queue()
        await self._input.put((message, out_q))
        while True:
            yield await out_q.get()  # HTTP handler reads from queue
```

### #14: SDK MCP Servers Completely Non-functional with String Prompts (Fixed in v0.1.81)
**Error**: SDK MCP servers created via `create_sdk_mcp_server()` are completely invisible to Claude when using string prompts. Tool calls either raise `CLIConnectionError: ProcessTransport is not ready for writing` or silently fail with the model unable to see any MCP tools ([#578](https://github.com/anthropics/claude-agent-sdk-python/issues/578), [#597](https://github.com/anthropics/claude-agent-sdk-python/issues/597))
**Cause**: Three root causes: (1) `sdkMcpServers` field was missing from the initialization control request in non-streaming mode, preventing CLI registration of SDK MCP servers; (2) String prompt code path closed stdin immediately after sending user message, blocking the control protocol; (3) `_stream_close_timeout` defaults to 60s, causing premature stdin close for long interactions.
**Fix** (v0.1.81): Root causes (1) and (2) are fully resolved — `query()` now always calls `initialize()` (sending `sdkMcpServers` to the CLI) and spawns `wait_for_result_and_end_input()` as a background task instead of awaiting it inline (PR [#780](https://github.com/anthropics/claude-agent-sdk-python/pull/780)). Root cause (3) was fixed in v0.1.81 ([#731](https://github.com/anthropics/claude-agent-sdk-python/issues/731)). Upgrade to v0.1.81+ — string prompts fully work with SDK MCP servers.
**Workaround (pre-v0.1.81 only)**: Use `AsyncIterable` prompt instead of string:
```python
async def prompt_gen():
    yield {"type": "text", "text": "Your prompt here"}

async for msg in query(prompt=prompt_gen(), options=options):
    ...
```

### #15: `rate_limit_event` Messages Crash `receive_messages()` Generator (Fixed in v0.1.44)
**Error**: `MessageParseError: Unknown message type: rate_limit_event` kills the async generator; no further messages are received from that session ([#601](https://github.com/anthropics/claude-agent-sdk-python/issues/601), [#583](https://github.com/anthropics/claude-agent-sdk-python/issues/583), [#603](https://github.com/anthropics/claude-agent-sdk-python/issues/603))
**Cause**: In versions before v0.1.44, `message_parser.py` used a strict allowlist of message types. When the CLI emitted a `rate_limit_event` (a new informational message), the strict match raised `MessageParseError` inside `yield`, terminating the generator permanently.
**Fix**: Fixed in v0.1.44. The message parser now silently skips unrecognized message types (returning `None`) instead of raising an exception, making it forward-compatible with new CLI message types. Upgrade to v0.1.44 or later to resolve.
**Workaround (pre-v0.1.44 only)**: Monkey-patch the message parser to swallow unknown message types:
```python
import claude_agent_sdk._internal.message_parser as _mp

_original_parse = _mp.parse_message

def _tolerant_parse(data):
    try:
        return _original_parse(data)
    except _mp.MessageParseError as e:
        if "Unknown message type" in str(e):
            return None  # Skip unknown types
        raise

_mp.parse_message = _tolerant_parse
# Apply to client module too
import claude_agent_sdk.client as _client_mod
if hasattr(_client_mod, 'parse_message'):
    _client_mod.parse_message = _tolerant_parse
```
Then filter `None` messages in your consumer: `if msg is not None: ...`

### #16: Session File Not Flushed Before Disconnect — Resume Fails
**Error**: Session resume fails silently — resume creates a new session instead of continuing the expected one, or session file contains only queue-operation lines with zero conversation data ([#584](https://github.com/anthropics/claude-agent-sdk-python/issues/584), [#555](https://github.com/anthropics/claude-agent-sdk-python/issues/555), [#625](https://github.com/anthropics/claude-agent-sdk-python/issues/625))
**Cause**: Two overlapping race conditions: (1) `ClaudeSDKClient.disconnect()` exits before async file write completes; (2) `SubprocessCLITransport.close()` sends SIGTERM immediately after stdin EOF without a graceful wait, killing the subprocess mid-write. Affects `query()` and `ClaudeSDKClient` alike. On NFS/shared storage, flush timing may require a longer sleep.
**Workaround**: Add a sleep before disconnecting to let the file flush (use 3+ seconds on NFS):
```python
import asyncio, time
from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions

client = ClaudeSDKClient(options=ClaudeAgentOptions(...))
await client.connect()
await client.query("Do some work")
async for msg in client.receive_response():
    pass
time.sleep(1)  # Wait for session file to flush (use 3+ on NFS)
await client.disconnect()
```
**Note**: The `async with` context manager does NOT apply this workaround automatically — use manual lifecycle if you need to resume the session.

### #17: `ProcessError.stderr` Contains Hardcoded String, Not Actual Error
**Error**: When catching `ProcessError`, `e.stderr` is always `"Check stderr output for details"` rather than the actual CLI error output ([#529](https://github.com/anthropics/claude-agent-sdk-python/issues/529), [#641](https://github.com/anthropics/claude-agent-sdk-python/issues/641))
**Cause**: The subprocess transport raises `ProcessError` with a hardcoded `stderr` string instead of the captured stderr content. Real error messages (e.g., `"No conversation found with session ID ab2c985b"`) are never surfaced in the exception. PR [#658](https://github.com/anthropics/claude-agent-sdk-python/pull/658) fixes this but is not yet released.
**Workaround**: Use the `stderr` callback option to capture actual CLI stderr output:
```python
import logging
logger = logging.getLogger("claude-sdk")
stderr_lines = []

options = ClaudeAgentOptions(
    stderr=lambda data: stderr_lines.append(data)
)

try:
    async for msg in query(prompt="...", options=options):
        pass
except ProcessError as e:
    # e.stderr is useless — use captured lines instead
    print("Actual error:", "\n".join(stderr_lines))
```

### #18: Global `~/.claude/settings.json` Overrides SDK Configuration
**Error**: SDK uses model or MCP servers from the user's global Claude Code settings instead of the programmatically configured values — causing unexpected model selection (e.g., Opus instead of Sonnet) and unintended MCP tool availability, leading to cost overruns ([#45](https://github.com/anthropics/claude-agent-sdk-python/issues/45))
**Cause**: The CLI subprocess loads `~/.claude/settings.json` on startup. Global settings (model, MCP servers, API keys in `env`) take precedence over or merge with SDK-provided options. The documentation's claim that "programmatic options always override filesystem settings" does not hold for all settings.
**Workaround**: Point the subprocess to an isolated home directory to prevent loading global settings:
```python
import os

options = ClaudeAgentOptions(
    model="claude-sonnet-4-5",
    env={
        **os.environ,
        "HOME": "/tmp/claude-sdk-home",  # Prevents loading ~/.claude/settings.json
    }
)
```
Ensure the isolated directory exists before running: `os.makedirs("/tmp/claude-sdk-home", exist_ok=True)`. You can also set `CLAUDE_CONFIG_DIR` to a unique per-run path if `HOME` override is too broad.

### #19: Passing `dict` as `options` Raises `AttributeError`
**Error**: `AttributeError: 'dict' object has no attribute 'can_use_tool'` when passing a plain dictionary to `query()` or `ClaudeSDKClient` ([#446](https://github.com/anthropics/claude-agent-sdk-python/issues/446))
**Cause**: The SDK expects a `ClaudeAgentOptions` dataclass instance. Internally it accesses attributes directly (`options.can_use_tool`), so a plain `dict` fails even though the documentation examples may suggest dicts are accepted. PR [#656](https://github.com/anthropics/claude-agent-sdk-python/pull/656) adds dict→`ClaudeAgentOptions` coercion but is not yet released.
**Fix**: Always instantiate `ClaudeAgentOptions` explicitly:
```python
# WRONG — dict raises AttributeError
await query(prompt="Hello", options={"max_turns": 5})

# CORRECT — use ClaudeAgentOptions
from claude_agent_sdk import ClaudeAgentOptions
await query(prompt="Hello", options=ClaudeAgentOptions(max_turns=5))
```

### #20: Multi-User Server Deployments Suffer Session Confusion
**Error**: In server deployments where multiple users share one process, Claude sessions interleave or concatenate responses across different users. Messages intended for user A appear in user B's session ([#632](https://github.com/anthropics/claude-agent-sdk-python/issues/632))
**Cause**: The CLI subprocess determines session identity from the working directory (`cwd`) and an auto-generated or reused session ID. When a `ClaudeSDKClient` instance is shared or when two concurrent requests use the same `cwd`, sessions collide. `ClaudeSDKClient` is not safe to reuse across concurrent ASGI request tasks (see also KI #13).
**Fix**: Isolate sessions per user with a unique `CLAUDE_CONFIG_DIR` and per-request `ClaudeSDKClient` instances:
```python
import os, uuid
from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions

async def handle_request(user_id: str, prompt: str):
    config_dir = f"/tmp/claude-sessions/{user_id}"
    os.makedirs(config_dir, exist_ok=True)
    options = ClaudeAgentOptions(
        env={**os.environ, "CLAUDE_CONFIG_DIR": config_dir}
    )
    async with ClaudeSDKClient(options=options) as client:
        await client.query(prompt)
        async for msg in client.receive_response():
            yield msg
```

### #21: `include_partial_messages=True` Breaks Tool Input Streaming on Bedrock/Vertex
**Error**: `400 Bad Request` with `"unexpected field: eager_input_streaming"` or tool input delta events stop arriving when using `include_partial_messages=True` with Bedrock, Vertex, or strict-schema proxies ([#644](https://github.com/anthropics/claude-agent-sdk-python/pull/644), [#671](https://github.com/anthropics/claude-agent-sdk-python/pull/671), [#694](https://github.com/anthropics/claude-agent-sdk-python/issues/694))
**Cause**: PR #644 (merged into v0.1.48) auto-enabled fine-grained tool streaming (`eager_input_streaming: true`) when `include_partial_messages=True`. This field is only accepted by the direct Anthropic API and Claude 4.6+. On Bedrock/Vertex or behind strict proxies the field causes 400 errors. PR #671 reverted #644 and is fully available in v0.1.50+. Users on v0.1.48 targeting Bedrock/Vertex are affected.
**Workaround**: To re-enable fine-grained tool streaming on a compatible endpoint, set the environment variable manually:
```python
options = ClaudeAgentOptions(
    include_partial_messages=True,
    env={**os.environ, "CLAUDE_CODE_ENABLE_FINE_GRAINED_TOOL_STREAMING": "1"}
)
```
Only set this variable when targeting the direct Anthropic API with Claude 4.6+. Omit it when using Bedrock, Vertex, or any proxy that rejects unknown fields.

### #22: Early Generator Exit Raises `RuntimeError` and Poisons Event Loop

**Error**: Breaking out of the `query()` async generator early causes `RuntimeError: Attempted to exit cancel scope in a different task than it was entered in`. In production, this error can poison the entire event loop — every subsequent `await` in that loop raises `CancelledError` ([#454](https://github.com/anthropics/claude-agent-sdk-python/issues/454))
**Cause**: The query task group's `__aenter__()` is called in one async context, but `__aexit__()` runs during generator cleanup in a different task context. AnyIO cancel scopes require enter/exit to happen in the same task. Occurs when using `async for msg in query(...): break` or when stopping after `ResultMessage`.
**Impact**: Production impact documented — once triggered, all subsequent `await` calls in that event loop get `CancelledError`. This affects parallel query execution with `asyncio.gather()`.
**Workaround**: Avoid breaking out of the generator early. If you must stop at `ResultMessage`, fully consume the generator:
```python
# RISKY — early break can poison event loop
async for msg in query(prompt="...", options=options):
    if isinstance(msg, ResultMessage):
        break  # May raise RuntimeError

# SAFER — consume all messages naturally
messages = []
async for msg in query(prompt="...", options=options):
    messages.append(msg)  # Generator exhausts naturally at ResultMessage

# PRODUCTION WORKAROUND — subprocess isolation per query
# (resource-intensive but guarantees clean event loop)
import subprocess, sys
result = subprocess.run([sys.executable, "-c", query_script], capture_output=True)
```

### #23: `thinking={"type":"disabled"}` Converted to `--max-thinking-tokens 0`, Breaking Compatible Providers (Fixed in v0.1.57)
**Error**: Providers that distinguish between *omitted* thinking settings and *explicitly disabled* thinking fail or behave unexpectedly when using `thinking={"type": "disabled"}` ([#693](https://github.com/anthropics/claude-agent-sdk-python/issues/693))
**Cause**: The SDK converts `thinking={"type": "disabled"}` to `--max-thinking-tokens 0` rather than transmitting the structured `thinking` configuration end-to-end. Anthropic-compatible providers (Bedrock, Vertex, third-party proxies) that parse the `thinking` field directly are affected. Similarly, `thinking={"type": "adaptive"}` was incorrectly mapped to `--max-thinking-tokens 32000` instead of a proper adaptive mode flag.
**Fix**: Resolved in v0.1.57 (PR [#796](https://github.com/anthropics/claude-agent-sdk-python/pull/796)). Correct flag mappings: `adaptive` → `--thinking adaptive`, `disabled` → `--thinking disabled`, `enabled` → `--max-thinking-tokens <budget_tokens>`. Upgrade to v0.1.57+.
**Workaround (v0.1.56 and earlier, pre-v0.1.57)**: Omit the `thinking` option entirely if the provider accepts "thinking not configured" as equivalent to disabled. If explicit disablement is required, there is no workaround — the SDK cannot currently pass the structured form.
```python
# WRONG on v0.1.56 and earlier — converts to --max-thinking-tokens 0 (breaks some providers)
options = ClaudeAgentOptions(thinking={"type": "disabled"})

# ALSO WRONG on v0.1.56 and earlier — adaptive maps to --max-thinking-tokens 32000, not --thinking adaptive
options = ClaudeAgentOptions(thinking={"type": "adaptive"})

# FIXED in v0.1.57+ — now correctly maps all thinking types
# WORKAROUND on v0.1.56 and earlier: omit entirely (provider interprets as no thinking)
options = ClaudeAgentOptions()  # No thinking configured
```

### #24: SDK MCP Server Tool Calls Fail with "Stream closed" After ~70 Seconds
**Error**: Tool calls to `create_sdk_mcp_server()` in-process servers return `"Stream closed"` errors after approximately 60–70 seconds of operation. Built-in tools (Read, Grep, Bash) continue working; only custom SDK MCP tools fail ([#676](https://github.com/anthropics/claude-agent-sdk-python/issues/676))
**Cause**: The bundled CLI does not reset its internal `lastActivityTime` counter when receiving responses from SDK MCP servers. After the inactivity threshold (~15s) is exceeded, subsequent MCP tool calls are immediately rejected. Built-in tools bypass this mechanism.
**Workaround**: Send periodic heartbeat activity from your MCP tool handler during long-running operations. If tools routinely take longer than 15 seconds, split work into smaller subtasks with intermediate responses. No SDK-level workaround; a CLI fix is required.

### #25: `output_format` Schema Not Enforced When Resuming Sessions
**Error**: When using `output_format` with `resume`, the JSON schema constraint is not applied to the resumed turn — the model responds in plain text instead of JSON ([#682](https://github.com/anthropics/claude-agent-sdk-python/issues/682))
**Cause**: CLI-level issue — schema constraints are not re-applied when loading prior session context. Both SDK flags are passed correctly, but the CLI drops the schema requirement when resuming.
**Workaround**: None currently. Avoid using `output_format` with `resume`/`continue_conversation`. Run structured output queries as fresh sessions.

### #26: PyPI Release Was Incomplete — Fixed in v0.1.50
**Error**: On Linux and Windows, only a `macosx_11_0_arm64` wheel was published to PyPI ([#687](https://github.com/anthropics/claude-agent-sdk-python/issues/687))
**Cause**: The automated release workflow uploaded the macOS ARM64 wheel successfully, then encountered a 400 error on the second upload. The remaining wheels (Linux x86_64/aarch64, Windows amd64, macOS x86_64) and the source distribution were not published.
**Fix**: **Resolved in v0.1.50.** Upgrade to v0.1.50 or later to get all features on all platforms:
```
pip install "claude-agent-sdk>=0.1.50"
```
These features — `AgentDefinition` fields (`skills`, `memory`, `mcpServers`), per-turn `usage` on `AssistantMessage`, `rename_session()`, `tag_session()`, and typed `RateLimitEvent` messages — are all available in v0.1.50 on all supported platforms.

### #27: `can_use_tool` Requires `AsyncIterable` Prompt — Raises `ValueError` with String Prompts
**Error**: `ValueError: can_use_tool callback requires streaming mode. Please provide prompt as an AsyncIterable instead of a string.` when `can_use_tool` is set and a string prompt is passed ([#469](https://github.com/anthropics/claude-agent-sdk-python/issues/469))
**Cause**: As of v0.1.78+, the SDK validates that `can_use_tool` is only used with `AsyncIterable` prompts. If a string prompt is passed, `ValueError` is raised immediately before any network call. Additionally, `can_use_tool` and `permission_prompt_tool_name` are mutually exclusive — using both raises `ValueError`. The SDK now auto-sets `permission_prompt_tool_name="stdio"` internally when `can_use_tool` is provided.
**Historical context**: In SDK v0.1.19–v0.1.56+, `can_use_tool` callbacks were silently never invoked even when correctly configured (CLI did not emit `can_use_tool` control protocol messages). As of v0.1.78+ the SDK enforces `AsyncIterable` mode (which keeps the control channel open), which may allow callbacks to actually fire — verify with your specific CLI version.
**Fix**: Use `AsyncIterable` prompt when using `can_use_tool`, or switch to `PreToolUse` hooks (recommended):
```python
# WRONG — raises ValueError with string prompt (v0.1.78+)
options = ClaudeAgentOptions(can_use_tool=my_permission_handler)
async for msg in query(prompt="...", options=options):  # ValueError!
    ...

# OPTION 1 — use AsyncIterable prompt
async def prompt_gen():
    yield {"type": "text", "text": "Your prompt here"}

async for msg in query(prompt=prompt_gen(), options=options):
    ...

# OPTION 2 (RECOMMENDED) — use PreToolUse hooks instead
async def permission_hook(input_data, tool_use_id, context):
    if input_data["tool_name"] == "Write":
        return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny"}}
    return {}

options = ClaudeAgentOptions(
    hooks={"PreToolUse": [HookMatcher(hooks=[permission_hook])]}
)
```

### #28: `DEBUG` Environment Variable Corrupts JSON Protocol in Docker/Linux
**Error**: SDK queries silently return no messages (or raise `Control request timeout: initialize`) when the `DEBUG` environment variable is set to any value in a Docker/Linux environment ([#347](https://github.com/anthropics/claude-agent-sdk-python/issues/347))
**Cause**: When `DEBUG` is set, the bundled Claude CLI's sandbox layer writes `[SandboxDebug]` diagnostic messages directly to **stdout** (not stderr). The SDK's `SubprocessCLITransport` reads all stdout lines and tries to parse them as JSON. The non-JSON debug lines accumulate in the buffer, causing all subsequent JSON parsing to fail — preventing the SDK from receiving any messages.
**Impact**: Affects Docker/Linux deployments (ARM64 or x64) where sandbox mode is active. macOS is unaffected. Setting `DEBUG=false` or `DEBUG=0` still triggers the issue (any non-empty value activates it).
**Workaround**: Override `DEBUG` to an empty string (or unset it) via the `env` option:
```python
import os
options = ClaudeAgentOptions(
    env={**os.environ, "DEBUG": ""},  # Suppress sandbox debug output to stdout
)
```
Alternatively, use `ANTHROPIC_LOG` instead of `DEBUG` for Anthropic SDK logging — it is not affected by this issue.

### #29: SDK MCP Server Tool Errors Not Propagated (`isError` Field Mismatch) (Fixed in v0.1.81)
**Error**: When an in-process SDK MCP tool handler raises an exception, Claude receives what appears to be a successful tool response — it doesn't know the tool failed. Additionally, any `"is_error": True` field in the tool handler's return dict is silently ignored ([#247](https://github.com/anthropics/claude-agent-sdk-python/issues/247))
**Cause**: The SDK's MCP handler checks `hasattr(result.root, "is_error")` using snake_case, but `mcp` library v1.x uses camelCase `isError`. The `hasattr()` check always returns `False`, so the error flag is never included in the JSON-RPC response to the CLI.
**Fix** (v0.1.81): `is_error` is now correctly propagated to the CLI (PR [#717](https://github.com/anthropics/claude-agent-sdk-python/issues/717)). Upgrade to v0.1.81+.
**Workaround** (v0.1.50 only): Include the error indication in the tool response *content* text, so Claude can read it:
```python
@tool("my_tool", "Do something", {"path": str})
async def my_tool(args: dict[str, Any]) -> dict[str, Any]:
    try:
        result = do_work(args["path"])
        return {"content": [{"type": "text", "text": result}]}
    except Exception as e:
        # Can't rely on is_error being propagated — include error in content
        return {"content": [{"type": "text", "text": f"ERROR: {e}"}]}
        # is_error=True is silently dropped on v0.1.50: {"is_error": True, ...} doesn't work
```

### #30: `query()` with Hooks Closes stdin After 60s, Killing Hook Callbacks (Fixed in v0.1.81)
**Error**: `Error in hook callback hook_0: ... Tool permission stream closed before response received` / `unhandled errors in a TaskGroup` when using `query()` with hooks on sessions longer than 60 seconds ([#730](https://github.com/anthropics/claude-agent-sdk-python/issues/730))
**Cause**: `query()` uses `wait_for_result_and_end_input()` which closes stdin after `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` (default 60s), even when hooks or SDK MCP servers are actively communicating. Once stdin closes, the CLI can no longer send hook callback requests, causing in-flight hooks to fail.
**Fix** (v0.1.81): stdin timeout is removed when hooks or SDK MCP servers are present (PR [#731](https://github.com/anthropics/claude-agent-sdk-python/issues/731)). Upgrade to v0.1.81+.
**Workaround** (v0.1.50 only): Raise the timeout to a large value:
```python
import os
os.environ["CLAUDE_CODE_STREAM_CLOSE_TIMEOUT"] = "3600000"  # 1 hour in ms
```
Or use `ClaudeSDKClient` instead of `query()`, which does not have this timeout issue.

### #31: `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` Ignored in `query()` Initialize Timeout (Fixed in v0.1.81)
**Error**: `query()` always times out at ~60 seconds during the CLI initialize handshake, regardless of `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` setting ([#741](https://github.com/anthropics/claude-agent-sdk-python/issues/741))
**Cause**: `ClaudeSDKClient.connect()` correctly reads `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` and passes `initialize_timeout` to `Query`, but `InternalClient.process_query()` (used by `query()`) creates `Query()` without the timeout, hardcoding 60s.
**Fix** (v0.1.81): `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` is now propagated to `query()` as well (PR [#743](https://github.com/anthropics/claude-agent-sdk-python/issues/743)). Upgrade to v0.1.81+.
**Workaround** (v0.1.50 only): Use `ClaudeSDKClient` instead of `query()` for long-running sessions — it correctly respects `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT`.

### #32: Bundled CLI v2.1.71 Ignores `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` on Bedrock
**Error**: `API Error: 400 tools.0.custom.eager_input_streaming: Extra inputs are not permitted` when using SDK v0.1.50 with AWS Bedrock, even with `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1` set ([#742](https://github.com/anthropics/claude-agent-sdk-python/issues/742))
**Cause**: The CLI bundled in v0.1.50 is v2.1.71, which has a known bug where `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1` does not suppress beta headers/features like `structured-outputs` and `eager_input_streaming`. Bedrock rejects these unknown fields. The bug was fixed in CLI v2.1.81+.
**Workaround**: Replace the bundled CLI with a globally installed version (v2.1.81+):
```bash
# Find bundled CLI location
python3 -c "import claude_agent_sdk, pathlib; print(pathlib.Path(claude_agent_sdk.__file__).parent)"
# Back up and symlink
mv <sdk_path>/bin/claude <sdk_path>/bin/claude.bak
ln -s $(which claude) <sdk_path>/bin/claude
```
Alternatively, set `cli_path` in your options to point to a newer CLI binary:
```python
options = ClaudeAgentOptions(cli_path="/usr/local/bin/claude")  # Points to v2.1.81+
```

### #33: `AssistantMessage` and `ResultMessage` Drop Significant Fields (Fixed in v0.1.81)
**Error**: Fields like `uuid`, `session_id`, `stop_reason`, and Anthropic message `id` were inaccessible in `AssistantMessage`. `ResultMessage` also dropped `model_usage` (per-model breakdown), `permission_denials`, `errors`, and `uuid` ([#562](https://github.com/anthropics/claude-agent-sdk-python/issues/562))
**Cause**: The message parser mapped only a fixed set of fields from the CLI JSON to typed dataclass fields; all other fields were discarded.
**Fix** (v0.1.81): `AssistantMessage` now exposes `message_id`, `stop_reason`, `session_id`, and `uuid`. `ResultMessage` now exposes `model_usage`, `permission_denials`, `errors`, and `uuid` (PR [#718](https://github.com/anthropics/claude-agent-sdk-python/issues/718)). Upgrade to v0.1.81+.
**Workaround** (v0.1.50 only): For per-turn usage, use `AssistantMessage.usage`. For session ID, read it from `SystemMessage(subtype="init")`.

### #34: `shutil.which()` Blocking Call Raises Error in Strict Async Environments (Fixed in v0.1.81)
**Error**: `BlockingError: shutil.which()` (or similar) raised when using the SDK in environments that prohibit synchronous I/O in async contexts (e.g., LangGraph with `blockbuster`, Trio with strict mode) ([#324](https://github.com/anthropics/claude-agent-sdk-python/issues/324))
**Cause**: The SDK calls `shutil.which("claude")` synchronously to locate the CLI binary during transport initialization. Tools like `blockbuster` treat any blocking filesystem call inside an async context as an error.
**Fix** (v0.1.81): CLI discovery is now deferred to `connect()` time and is non-blocking (PR [#722](https://github.com/anthropics/claude-agent-sdk-python/issues/722)). Upgrade to v0.1.81+.
**Workaround** (v0.1.50 only): Provide the CLI path explicitly to bypass the `which()` call:
```python
import shutil
options = ClaudeAgentOptions(
    cli_path=shutil.which("claude")  # Resolve path before entering async context
)
```

### #35: `connect(prompt=str)` Silently Drops Prompt — `receive_messages()` Hangs (Fixed in v0.1.81)
**Error**: Calling `await client.connect(prompt="your prompt")` followed by `async for msg in client.receive_messages()` hangs indefinitely and never yields any messages. No error is raised ([#766](https://github.com/anthropics/claude-agent-sdk-python/issues/766))
**Cause**: `connect()` stored the string prompt internally but never wrote it to stdin. The transport was connected but no user message was dispatched, so the CLI waited forever for input.
**Fix** (v0.1.81): String prompts are now wrapped in a user message and sent to stdin in `connect()` (PR [#769](https://github.com/anthropics/claude-agent-sdk-python/pull/769)). Upgrade to v0.1.81+.
**Workaround** (pre-v0.1.81): Use `connect()` without a prompt, then call `query()` separately:
```python
# WRONG on pre-v0.1.81 — prompt silently dropped
await client.connect(prompt="Say hello")
async for msg in client.receive_messages(): ...

# CORRECT on all versions
await client.connect()
await client.query("Say hello")
async for msg in client.receive_messages(): ...
```

### #36: `ExitPlanMode` Terminates Current SDK Turn — No Subsequent Tool Execution
**Error**: When using `plan` permission mode with `ClaudeSDKClient`, after the model calls `ExitPlanMode`, the current turn ends immediately (a `ResultMessage` is emitted) and no further tool calls from that same turn are executed. Actions planned before exiting plan mode are never carried out ([#774](https://github.com/anthropics/claude-agent-sdk-python/issues/774))
**Cause**: The SDK treats `ExitPlanMode` as a turn-ending signal equivalent to a normal completion. The expected workflow (plan → get approval → exit plan mode → execute) cannot run in a single turn.
**Impact**: Multi-step plan-then-execute workflows that rely on a single query call will silently drop all post-plan actions.
**Workaround**: Detect the `ResultMessage` after `ExitPlanMode` and send a follow-up `query()` call to trigger execution:
```python
async with ClaudeSDKClient(options=ClaudeAgentOptions(permission_mode="plan")) as client:
    await client.query("Plan and implement feature X")
    async for msg in client.receive_response():
        pass  # plan turn ends at ExitPlanMode
    # Send follow-up to execute the plan
    await client.query("Now execute the plan you described")
    async for msg in client.receive_response():
        print(msg)
```

### #37: `PreToolUse` `updatedInput` Has No Effect on `AskUserQuestion` Tool
**Error**: Returning `updatedInput` from a `PreToolUse` hook for the `AskUserQuestion` tool has no effect — the tool result Claude sees does not reflect the modified input. Claude proceeds as if no answer was provided ([#767](https://github.com/anthropics/claude-agent-sdk-python/issues/767))
**Cause**: The `AskUserQuestion` tool processes its input directly from the tool call rather than reading back the hook-modified input. The `updatedInput` mechanism works for most tools but is silently ignored for `AskUserQuestion`.
**Workaround**: Use `permissionDecision: "deny"` with the answer embedded in `permissionDecisionReason` instead:
```python
async def ask_hook(input_data, tool_use_id, context):
    # updatedInput is ignored for AskUserQuestion — use deny+reason instead
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "The user has already provided their answer: Jeremy",
        }
    }

options = ClaudeAgentOptions(
    permission_mode="bypassPermissions",
    hooks={"PreToolUse": [HookMatcher(matcher="AskUserQuestion", hooks=[ask_hook])]},
)
```

### #38: `bypassPermissions` Mode Skips settings.json Shell Hooks
**Error**: Shell hooks configured in `~/.claude/settings.json` (e.g., `PreToolUse` hooks with `"type": "command"`) are never executed when `permission_mode="bypassPermissions"` is set via the SDK. The same hooks fire correctly when running `claude --dangerously-skip-permissions` directly from the CLI ([#768](https://github.com/anthropics/claude-agent-sdk-python/issues/768))
**Cause**: CLI-level issue — when the SDK starts the subprocess with `bypassPermissions`, the hook invocation path is bypassed before reaching filesystem-configured shell hooks.
**Impact**: Any shell hooks in global `~/.claude/settings.json` are silently skipped in `bypassPermissions` mode. This includes pre-tool validation scripts, audit logging hooks, and notification hooks.
**Workaround**: Use Python hook callbacks via `ClaudeAgentOptions.hooks` instead of shell hooks in settings.json:
```python
import subprocess

async def shell_hook_wrapper(input_data, tool_use_id, context):
    # Replicate your shell hook logic in Python
    result = subprocess.run(["/path/to/hook.sh"], capture_output=True)
    return {}

options = ClaudeAgentOptions(
    permission_mode="bypassPermissions",
    hooks={"PreToolUse": [HookMatcher(hooks=[shell_hook_wrapper])]},
)
```

### #39: SDK Does Not Resolve User-Installed Skills (Slash Commands)
**Error**: When a prompt starts with a slash command (e.g., `/my-skill`) or when skills are installed via plugins in `~/.claude/plugins/`, they are not found by the SDK — the response is `"Unknown skill"` immediately with $0 cost ([#765](https://github.com/anthropics/claude-agent-sdk-python/issues/765), [#509](https://github.com/anthropics/claude-agent-sdk-python/issues/509))
**Cause**: The CLI subprocess spawned by the SDK does not discover skills from the user's global skills directory or from plugin-installed paths unless the skill files are present in the project's `.claude/skills/` directory.
**Workaround**: Copy skill files into `.claude/skills/` inside the `cwd` directory. Note that this bypasses automatic skill updates from plugins:
```python
import shutil, os

# Copy skill from user-global location to project-local location
src = os.path.expanduser("~/.claude/skills/my-skill.md")
dst = os.path.join(project_dir, ".claude", "skills", "my-skill.md")
os.makedirs(os.path.dirname(dst), exist_ok=True)
shutil.copy2(src, dst)

# Now the SDK can find the skill
options = ClaudeAgentOptions(cwd=project_dir)
async for msg in query(prompt="/my-skill", options=options):
    print(msg)
```
Alternatively, use `setting_sources=["user", "project", "local"]` with the skill referenced in CLAUDE.md — this may help the CLI discover plugin-installed skills in some configurations.

### #40: `setting_sources=[]` Silently Ignored — No Way to Fully Isolate from Filesystem Settings
**Error**: Passing `setting_sources=[]` to disable all setting sources has no effect; the CLI still loads its default settings ([#794](https://github.com/anthropics/claude-agent-sdk-python/issues/794))
**Cause**: Two compounding bugs: (1) SDK uses a truthiness check (`if self._options.setting_sources:`) rather than a `None` check, so an empty list evaluates to `False` and the `--setting-sources` flag is never passed to the CLI. (2) Even if the flag were passed with an empty value, the CLI silently ignores it and falls back to defaults.
**Impact**: There is currently **no way to fully isolate an SDK application from all filesystem settings** (e.g., `~/.claude/settings.json`). This is relevant when running multi-tenant servers where per-user settings should not bleed into SDK queries.
**Partial workaround**: `setting_sources=["project"]` excludes user-level settings (`~/.claude/`) but still loads `.claude/settings.json` if present in the `cwd`. See also [Known Issue #18](#18-global-claudesettingsjson-overrides-sdk-configuration) for the broader settings override problem.
```python
# WRONG — empty list is falsy, flag is silently omitted, all settings still load
options = ClaudeAgentOptions(setting_sources=[])

# WRONG — [""] passes the flag but CLI ignores empty strings, still loads all settings
options = ClaudeAgentOptions(setting_sources=[""])

# PARTIAL WORKAROUND — excludes ~/.claude/ but still loads .claude/settings.json in cwd
options = ClaudeAgentOptions(setting_sources=["project"])

# Use None (default) to load all sources explicitly
options = ClaudeAgentOptions(setting_sources=None)
```

### #41: `ThinkingBlock` Missing `signature` Field Crashes Message Parser
**Error**: `KeyError: 'signature'` (or a `CLIJSONDecodeError`) when iterating messages if the API returns a thinking content block without a `signature` field ([#786](https://github.com/anthropics/claude-agent-sdk-python/pull/786))
**Cause**: The message parser does a direct dictionary key access for `signature` when constructing `ThinkingBlock`. Redacted thinking blocks (when extended thinking is active but the model elides the signature for safety reasons) and certain streaming edge cases can produce a thinking block without this field. The fix (using `.get("signature", "")`) is in open PR [#786](https://github.com/anthropics/claude-agent-sdk-python/pull/786), not yet released.
**Workaround**: Wrap message iteration in a try/except to skip malformed thinking blocks:
```python
from claude_agent_sdk import CLIJSONDecodeError

try:
    async for msg in query(prompt="...", options=options):
        process(msg)
except (KeyError, CLIJSONDecodeError) as e:
    if "signature" in str(e):
        pass  # Skip redacted/malformed thinking blocks
    else:
        raise
```
Alternatively, avoid using `thinking={"type": "enabled", ...}` in contexts where redacted thinking is likely (e.g., safety-filtered responses).

### #42: Background `TaskNotificationMessage` Leaks Into Next `receive_response()` Turn
**Error**: When a background task (spawned via the `Task` tool with `run_in_background=true`) completes between turns, its `TaskNotificationMessage` leaks into the next `receive_response()` call. Claude responds to the stale notification instead of the new user prompt, producing unexpected or empty responses ([#788](https://github.com/anthropics/claude-agent-sdk-python/issues/788))
**Cause**: CLI sends the task completion notification asynchronously; the Python SDK does not suppress stale inter-turn task messages. A fix PR ([#791](https://github.com/anthropics/claude-agent-sdk-python/issues/791)) is open but not yet released.
**Workaround**: Track pending task IDs and detect/discard contaminated turns, then re-send the prompt:
```python
from claude_agent_sdk import (
    ClaudeSDKClient, ClaudeAgentOptions,
    TaskStartedMessage, TaskNotificationMessage, ResultMessage
)

async def smart_turn(client, prompt, stale_ids, max_retries=5):
    """Sends a query and retries if a stale TaskNotification leaks into the turn."""
    for attempt in range(max_retries):
        await client.query(prompt)
        found_stale = False
        async for msg in client.receive_response():
            if isinstance(msg, TaskNotificationMessage) and msg.task_id in stale_ids:
                found_stale = True  # Stale notification leaked — discard this turn
            if isinstance(msg, ResultMessage):
                break
        if not found_stale:
            return  # Clean turn — done
        # Stale turn detected — retry
```
To use: pass a `stale_ids` set containing task IDs from `TaskStartedMessage` objects seen in the previous turn that had not yet emitted a `TaskNotificationMessage`.

### #43: Newer CLI Versions Break OpenRouter and Third-Party Providers (`context-management` Beta Header)
**Error**: `API Error: 400 No endpoints available that support Anthropic's context management features (context-management-2025-06-27). Context management requires a supported provider (Anthropic).` when using SDK v0.1.46+ with OpenRouter or other third-party Anthropic-compatible providers ([#789](https://github.com/anthropics/claude-agent-sdk-python/issues/789))
**Cause**: CLI versions after 2.1.63 (SDK ≥ v0.1.46) include the `context-management-2025-06-27` beta header in API requests. Third-party providers (OpenRouter, local proxies, self-hosted endpoints) reject this unknown header with a 400 error. There is currently no SDK-level option to suppress it.
**Workaround**: Either pin to an older SDK version (≤ v0.1.45, bundled with CLI ≤ 2.1.63) or point `cli_path` to a locally installed older CLI binary:
```python
import subprocess, shutil

# Option 1: pin in requirements.txt
# claude-agent-sdk==0.1.45

# Option 2: use a globally installed older CLI to bypass the bundled one
options = ClaudeAgentOptions(
    cli_path=shutil.which("claude"),  # Must be CLI ≤ 2.1.63; verify with: claude --version
    model="openai/gpt-4o",           # Or your provider's model alias
)
```
**Note**: Pinning to v0.1.45 loses all SDK improvements since that version (no `task_budget`, no `get_context_usage()`, no `exclude_dynamic_sections`, no background task messages, etc.). Monitor [#789](https://github.com/anthropics/claude-agent-sdk-python/issues/789) for an official fix.

---

## Changelog Highlights

| Version | Change |
|---------|--------|
| v0.1.81 | Patch release; no Python API changes. `permissionDecision: "defer"` added to `PreToolUseHookSpecificOutput` — stops the run and exposes the deferred call in `ResultMessage.deferred_tool_use` for human-in-the-loop approval workflows. |
| v0.1.81 | Bundled CLI updated to v2.1.138 (no Python API changes) |
| v0.1.78–v0.1.79 | `can_use_tool` now raises `ValueError` when used with a string prompt — use `AsyncIterable` prompt instead. The SDK automatically sets `permission_prompt_tool_name="stdio"` internally when `can_use_tool` is provided, activating the control protocol. `can_use_tool` and `permission_prompt_tool_name` are now mutually exclusive (raises `ValueError` if both set). See [#27](#27-can_use_tool-requires-asynciterable-prompt--raises-valueerror-with-string-prompts). |
| v0.1.81 | Bundled CLI updated to v2.1.133 (no Python API changes) |
| v0.1.81 | `strict_mcp_config` option added to `ClaudeAgentOptions` (bool, default `False`) — ignore all other MCP sources and use only `mcp_servers`; `include_hook_events` option added (bool, default `False`) — emit `HookEventMessage` objects into the message stream; `effort` extended with `"xhigh"` level for Opus 4.7+; `ToolPermissionContext` gains `blocked_path`, `decision_reason`, `title`, `display_name`, `description` fields; `ResultMessage` gains `deferred_tool_use` (for `permissionDecision: "defer"` hooks) and `api_error_status` (HTTP status of failing API call); `PostToolUseHookSpecificOutput` gains `updatedToolOutput` (works for all tools, not just MCP) |
| v0.1.81 | `session_store_flush` option added to `ClaudeAgentOptions` (`SessionStoreFlushMode`: `"batched"` \| `"eager"`, default `"batched"`) — controls when mirrored entries are flushed to `session_store`; bundled CLI updated to v2.1.128 |
| v0.1.81 | Bundled CLI updated to v2.1.126 (no Python API changes); `mcp` dependency floor raised to `>=1.19.0` |
| v0.1.81 | `SandboxNetworkConfig` extended with `allowedDomains`, `deniedDomains`, `allowManagedDomainsOnly`, and `allowMachLookup` fields for finer-grained network sandbox control |
| v0.1.70 | Minor patch release (no Python API changes) |
| v0.1.81 | Bundled CLI updated to v2.1.121 (no Python API changes) |
| v0.1.81 | `claude_agent_sdk.testing` subpackage added — exports `run_session_store_conformance()`, a shared conformance suite that validates all 14 `SessionStore` behavioral contracts; works with any async test runner (no pytest required); `fold_session_summary()` signature updated to `(prev, key, entries)` — `key: SessionKey` is now a required second argument; bundled CLI updated to v2.1.119 |
| v0.1.81 | `ThinkingDisplay = Literal["summarized", "omitted"]` type added (Opus 4.7+ defaults to `"omitted"`); optional `display` field added to `ThinkingConfigAdaptive` and `ThinkingConfigEnabled`; `import_session_to_store()` async function exported — replays a local on-disk session into a `SessionStore` for migration or gap-recovery after `MirrorErrorMessage` |
| v0.1.81 | `SessionSummaryEntry` type and `fold_session_summary()` helper added — enables efficient incremental summary maintenance in `SessionStore.list_session_summaries()` without full JSONL re-reads; `SessionStore` Protocol gains optional `list_session_summaries()` method; `ServerToolUseBlock` and `ServerToolResultBlock` content block types exposed (server-side tool events the API executes on the model's behalf); `ServerToolName` literal type added |
| v0.1.81 | Session Store API added: `SessionStore` Protocol, `InMemorySessionStore`, `project_key_for_directory`; store-backed session read/mutation functions (`list_sessions_from_store`, `get_session_info_from_store`, `get_session_messages_from_store`, `list_subagents_from_store`, `get_subagent_messages_from_store`, `rename_session_via_store`, `tag_session_via_store`, `delete_session_via_store`, `fork_session_via_store`); `session_store` and `load_timeout_ms` options added to `ClaudeAgentOptions`; `MirrorErrorMessage` emitted when store `append()` fails |
| v0.1.81 | Bundled CLI updated to v2.1.114 (no Python API changes) |
| v0.1.62 | `ClaudeAgentOptions.skills` field added (`list[str] \| Literal["all"] \| None`) — controls which skills the main session can use; SDK auto-configures `allowed_tools` and `setting_sources` when set |
| v0.1.81 | `list_subagents()` and `get_subagent_messages()` added — read subagent transcripts from `<sessionId>/subagents/agent-<agentId>.jsonl`; supports nested workflow subdirectories |
| v0.1.60 | Minor patch release (no Python API changes) |
| v0.1.81 | Bundled CLI updated to v2.1.105 (no Python API changes) |
| v0.1.81 | Bundled CLI updated to v2.1.92 (no API changes) |
| v0.1.81 | MCP large tool results: `ToolAnnotations.maxResultSizeChars` now correctly forwarded to CLI via `_meta`, fixing silent truncation of large tool results ([#756](https://github.com/anthropics/claude-agent-sdk-python/issues/756)); bundled CLI updated to v2.1.91 |
| v0.1.81 | `SessionStartHookSpecificOutput` type added to `HookSpecificOutput` union in preparation for future `SessionStart` hook event (not yet in `HookEvent` union) |
| v0.1.81 | `AgentDefinition` gains `background`, `effort`, and `permissionMode` fields; `list_sessions()` gains `offset` parameter |
| v0.1.81 | Fixed string prompt deadlock when hooks/MCP servers trigger many tool calls — `wait_for_result_and_end_input()` now spawned as background task ([#780](https://github.com/anthropics/claude-agent-sdk-python/pull/780)); fixed `--setting-sources` being passed as empty string when unset ([#778](https://github.com/anthropics/claude-agent-sdk-python/issues/778)); SDK MCP servers now fully functional with string prompts (see [#14](#14-sdk-mcp-servers-completely-non-functional-with-string-prompts)) |
| v0.1.81 | `delete_session()` and `fork_session()` (offline session forking with `up_to_message_id` support) added; `ForkSessionResult` dataclass; `get_context_usage()` method on `ClaudeSDKClient` returns `ContextUsageResponse`; `session_id` field added to `ClaudeAgentOptions`; `ToolPermissionContext` now exposes `tool_use_id` and `agent_id` fields |
| v0.1.81 | `dontAsk` added to `PermissionMode`; `is_error` propagated from SDK MCP tools ([#717](https://github.com/anthropics/claude-agent-sdk-python/issues/717)); `AssistantMessage`/`ResultMessage` expose dropped fields as typed attributes ([#718](https://github.com/anthropics/claude-agent-sdk-python/issues/718)); `resource_link`/`embedded_resource`/`audio` content types in SDK MCP tools ([#725](https://github.com/anthropics/claude-agent-sdk-python/issues/725)); SIGKILL fallback in `close()` ([#729](https://github.com/anthropics/claude-agent-sdk-python/issues/729)); stdin timeout removed for hooks/MCP servers ([#731](https://github.com/anthropics/claude-agent-sdk-python/issues/731)); `CLAUDECODE` env var automatically filtered ([#732](https://github.com/anthropics/claude-agent-sdk-python/issues/732)); non-blocking CLI discovery ([#722](https://github.com/anthropics/claude-agent-sdk-python/issues/722)); `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` respected by `query()` ([#743](https://github.com/anthropics/claude-agent-sdk-python/issues/743)); `SystemPromptFile` support added; `AgentDefinition` fields `disallowedTools`, `initialPrompt`, `maxTurns` added; `task_budget` option added; `connect(prompt=str)` now correctly sends the prompt instead of silently dropping it ([#769](https://github.com/anthropics/claude-agent-sdk-python/pull/769)); `control_cancel_request` messages now properly cancel in-flight hook callbacks ([#751](https://github.com/anthropics/claude-agent-sdk-python/pull/751)); `@tool` `input_schema` supports `typing.Annotated` for per-parameter descriptions ([#762](https://github.com/anthropics/claude-agent-sdk-python/pull/762)); bundled CLI updated to v2.1.87 |
| v0.1.57 | `auto` added to `PermissionMode`; `SystemPromptPreset.exclude_dynamic_sections` field added (strips per-user dynamic sections for cross-user cache hits); `thinking` flag mapping fixed — `adaptive` now sends `--thinking adaptive`, `disabled` sends `--thinking disabled` instead of `--max-thinking-tokens 0` (PR [#796](https://github.com/anthropics/claude-agent-sdk-python/pull/796)) |
| v0.1.50 | Full cross-platform release. All platforms now get: `skills`, `memory`, `mcpServers` on `AgentDefinition`; `usage` field on `AssistantMessage`; `rename_session()`, `tag_session()`; typed `RateLimitEvent`/`RateLimitInfo` message types; reverted Bedrock-breaking eager_input_streaming (see [#26](#26-pypi-release-was-incomplete--fixed-in-v0150)) |
| v0.1.48 | Introduced `eager_input_streaming` with `include_partial_messages=True` (breaks Bedrock/Vertex — see [#21](#21-include_partial_messagestrue-breaks-tool-input-streaming-on-bedrockvertex)) |
| v0.1.44 | Fixed `rate_limit_event` crash in message parser — unknown CLI message types now skipped gracefully; bundled CLI updated to v2.1.59 |
| v0.1.36 | Added `thinking` (`ThinkingConfig` types: adaptive/enabled/disabled) and `effort` options; deprecated `max_thinking_tokens` |
| v0.1.35 | Sub-agent registration via `@filepath` syntax fixed; agents now reliably registered |
| v0.1.0 | Breaking: `ClaudeCodeOptions` renamed to `ClaudeAgentOptions`; no default system prompt; no filesystem settings loaded by default |

---

**Last verified**: 2026-05-14 | **SDK version**: 0.1.81