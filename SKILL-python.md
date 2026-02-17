# Claude Agent SDK — Python Reference (v0.1.37)

**Package**: `claude-agent-sdk==0.1.37` (PyPI)
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
- [Message Types](#message-types) — `Message` union, content blocks, errors
- [Hooks](#hooks) — 10 hook events, matchers, return values, async hooks
- [Permissions](#permissions) — 4 modes, `can_use_tool` callback
- [MCP Servers](#mcp-servers) — stdio, HTTP, SSE, SDK in-process
- [Subagents](#subagents) — `AgentDefinition`, tool enforcement
- [Extended Thinking](#extended-thinking) — `ThinkingConfig`, `effort`
- [Structured Outputs](#structured-outputs)
- [Sandbox](#sandbox)
- [Sessions](#sessions)
- [Debugging & Error Handling](#debugging--error-handling)
- [Known Issues](#known-issues)
- [Changelog Highlights](#changelog-highlights)

---

## Breaking Changes (v0.1.0)

1. **No default system prompt** — SDK uses minimal prompt. Use `system_prompt={"type": "preset", "preset": "claude_code"}` for old behavior.
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
    options: ClaudeAgentOptions | None = None
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
    def __init__(self, options: ClaudeAgentOptions | None = None) -> None: ...
    async def connect(self, prompt: str | AsyncIterable[dict] | None = None) -> None: ...
    async def query(self, prompt: str | AsyncIterable[dict], session_id: str = "default") -> None: ...
    async def receive_messages(self) -> AsyncIterator[Message]: ...
    async def receive_response(self) -> AsyncIterator[Message]: ...
    async def interrupt(self) -> None: ...
    async def rewind_files(self, user_message_uuid: str) -> None: ...
    async def set_permission_mode(self, mode: str) -> None: ...
    async def set_model(self, model: str | None = None) -> None: ...
    async def get_mcp_status(self) -> dict[str, Any]: ...
    async def get_server_info(self) -> dict[str, Any] | None: ...
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
| **Hooks**           | No                            | Yes                                |
| **Custom Tools**    | No                            | Yes                                |
| **Continue Chat**   | No (new session each time)    | Yes (maintains conversation)       |

### `@tool()`

Decorator for defining MCP tools.

```python
from claude_agent_sdk import tool
from typing import Any
from mcp.types import ToolAnnotations

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

2. **JSON Schema format** (for complex validation):
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

---

## Options

### Core Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `model` | `str \| None` | `None` | Claude model to use |
| `cwd` | `str \| Path \| None` | `None` | Working directory |
| `system_prompt` | `str \| SystemPromptPreset \| None` | `None` | System prompt or preset dict |
| `setting_sources` | `list[SettingSource] \| None` | `None` | `"user" \| "project" \| "local"` |
| `env` | `dict[str, str]` | `{}` | Environment variables |
| `cli_path` | `str \| Path \| None` | `None` | Custom path to Claude Code CLI |

### Tools & Permissions

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `tools` | `list[str] \| ToolsPreset \| None` | `None` | Tool configuration |
| `allowed_tools` | `list[str]` | `[]` | Allowed tool names |
| `disallowed_tools` | `list[str]` | `[]` | Blocked tool names |
| `permission_mode` | `PermissionMode \| None` | `None` | See [Permissions](#permissions) for all 4 modes |
| `can_use_tool` | `CanUseTool \| None` | `None` | Custom permission callback |
| `permission_prompt_tool_name` | `str \| None` | `None` | Route permission prompts through a named MCP tool |

### Models & Output

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `output_format` | `OutputFormat \| None` | `None` | `{"type": "json_schema", "schema": dict}` |
| `max_thinking_tokens` | `int \| None` | `None` | **Deprecated** — use `thinking` instead |
| `thinking` | `ThinkingConfig \| None` | `None` | Extended thinking configuration (adaptive/enabled/disabled) |
| `effort` | `Literal["low", "medium", "high", "max"] \| None` | `None` | Effort level for thinking depth |
| `fallback_model` | `str \| None` | `None` | Fallback model on failure |
| `betas` | `list[SdkBeta]` | `[]` | Beta features (e.g., `["context-1m-2025-08-07"]`) |
| `include_partial_messages` | `bool` | `False` | Include streaming partial `StreamEvent` messages |

### Sessions

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `resume` | `str \| None` | `None` | Session ID to resume |
| `fork_session` | `bool` | `False` | Fork when resuming |
| `continue_conversation` | `bool` | `False` | Continue most recent conversation |
| `max_turns` | `int \| None` | `None` | Max conversation turns (critical safety net) |
| `max_budget_usd` | `float \| None` | `None` | Max budget in USD |
| `enable_file_checkpointing` | `bool` | `False` | Enable file rollback via `rewind_files()` |

### MCP & Agents

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `mcp_servers` | `dict[str, McpServerConfig] \| str \| Path` | `{}` | MCP server configs or path to config file |
| `agents` | `dict[str, AgentDefinition] \| None` | `None` | Subagent definitions |
| `plugins` | `list[SdkPluginConfig]` | `[]` | `{"type": "local", "path": str}` |

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
await client.rewind_files(user_message_uuid)        # Rewind files to checkpoint
await client.set_permission_mode(mode)              # Change permission mode mid-conversation
await client.set_model(model)                       # Switch AI model mid-conversation
status = await client.get_mcp_status()              # Get MCP server connection status
info = await client.get_server_info()               # Get server initialization info
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

The SDK emits 5 message types:

```python
from claude_agent_sdk import (
    UserMessage, AssistantMessage, SystemMessage, ResultMessage, StreamEvent
)

Message = UserMessage | AssistantMessage | SystemMessage | ResultMessage | StreamEvent
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
    total_cost_usd: float | None = None
    usage: dict[str, Any] | None = None
    result: str | None = None
    structured_output: Any = None
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

### Content Block Types

```python
ContentBlock = TextBlock | ThinkingBlock | ToolUseBlock | ToolResultBlock

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

Hooks use **callback matchers**: an optional regex `matcher` for tool names and a list of `hooks` callbacks. Hooks are only available with `ClaudeSDKClient`, not the standalone `query()` function.

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

**Not supported in Python SDK**: `Setup`, `SessionStart`, `SessionEnd`, `TeammateIdle`, `TaskCompleted`.

### Hook Callback Signature

```python
from claude_agent_sdk import HookContext
from typing import Any

async def my_hook(
    input_data: dict[str, Any],
    tool_use_id: str | None,
    context: HookContext
) -> dict[str, Any]:
    ...
```

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

# Modify tool input (PreToolUse only, requires permissionDecision: 'allow')
return {
    "hookSpecificOutput": {
        "hookEventName": input_data["hook_event_name"],
        "permissionDecision": "allow",
        "updatedInput": {**input_data["tool_input"], "file_path": f"/sandbox{path}"},
    }
}

# Modify MCP tool output (PostToolUse only)
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
| `tool_response` | PostToolUse |
| `error`, `is_interrupt` | PostToolUseFailure |
| `prompt` | UserPromptSubmit |
| `stop_hook_active` | Stop, SubagentStop |
| `agent_id`, `agent_type` | SubagentStart, SubagentStop |
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
]
```

**Note**: The Python SDK exposes 4 permission modes. The TypeScript SDK additionally has `"delegate"` and `"dontAsk"`.

### `can_use_tool`

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
    suggestions: list[PermissionUpdate] = field(default_factory=list)
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

    def to_dict(self) -> dict[str, Any]: ...  # Converts to TypeScript control protocol format
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
    model: Literal["sonnet", "opus", "haiku", "inherit"] | None = None
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
from claude_agent_sdk.types import ThinkingConfig

# Adaptive mode - Claude decides when to think
ThinkingConfigAdaptive = {"type": "adaptive"}

# Enabled mode - budget-limited thinking
ThinkingConfigEnabled = {"type": "enabled", "budget_tokens": int}

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
    allowLocalBinding: bool                    # Allow binding to local ports
    allowUnixSockets: list[str]                # Specific Unix socket paths
    allowAllUnixSockets: bool
    httpProxyPort: int
    socksProxyPort: int

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

```python
async with ClaudeSDKClient(
    options=ClaudeAgentOptions(enable_file_checkpointing=True)
) as client:
    await client.query("Refactor auth module")
    async for msg in client.receive_response():
        pass
    # Rewind to a specific user message checkpoint
    await client.rewind_files(user_message_uuid)
```

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

### #2: Empty `allowed_tools=[]` Allows All Tools
**Error**: Passing `allowed_tools=[]` to restrict all tools fails silently; all tools become available instead ([#523](https://github.com/anthropics/claude-agent-sdk-python/issues/523))
**Cause**: Empty list is treated as falsy in Python, causing `--allowedTools` flag to be omitted from CLI command.
**Fix**: Use `allowed_tools=None` for default behavior, or pass a dummy tool name if you need to restrict tools programmatically. A proper fix would check `if allowed_tools is not None` instead of truthiness.

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

### #9: Thinking Blocks Missing with Opus 4.6 (Fixed in v0.1.37)
**Error**: No thinking blocks returned when using `claude-opus-4-6` with `max_thinking_tokens` ([#553](https://github.com/anthropics/claude-agent-sdk-python/issues/553))
**Cause**: Opus 4.6 deprecated `budget_tokens` in favor of adaptive thinking.
**Fix**: Use `thinking={"type": "adaptive"}` and `effort="high"` instead of `max_thinking_tokens`. Fixed in v0.1.37 with addition of `thinking` and `effort` options.

### #10: SDK Usage Blocked Inside Claude Code Sessions (Hooks/Plugins)
**Error**: `Error: Claude Code cannot be launched inside another Claude Code session.` when using SDK from hooks, plugins, or subagents ([#573](https://github.com/anthropics/claude-agent-sdk-python/issues/573))
**Cause**: Subprocess inherits `CLAUDECODE=1` environment variable from parent Claude Code process. The spawned CLI detects this and refuses to start.
**Fix**: Override the variable via the `env` option:
```python
options = ClaudeAgentOptions(
    env={"CLAUDECODE": ""},
    # ... other options
)
```

### #11: `search_result` Content Blocks Silently Dropped
**Error**: Custom MCP tools returning `search_result` content blocks have those blocks silently dropped before reaching Claude, breaking RAG citations ([#574](https://github.com/anthropics/claude-agent-sdk-python/issues/574))
**Cause**: SDK's MCP tool result handler only recognizes `text` and `image` content types; `search_result` blocks fall through and are discarded.
**Impact**: Cannot use [native citations](https://platform.claude.com/docs/en/build-with-claude/search-results) with custom RAG tools in the Agent SDK.
**Workaround**: None. Bypass SDK and use `anthropic.AsyncAnthropic` directly for RAG workflows requiring citations.

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

### #14: SDK MCP Servers Crash with String Prompts
**Error**: `CLIConnectionError: ProcessTransport is not ready for writing` when using in-process MCP servers (from `create_sdk_mcp_server()`) with string prompts ([#578](https://github.com/anthropics/claude-agent-sdk-python/issues/578))
**Cause**: String prompt code path closes stdin immediately after sending user message. SDK MCP servers require bidirectional communication (CLI sends `control_request` via stdout, SDK responds via stdin), but stdin is already closed.
**Workaround**: Use `AsyncIterable` prompt instead of string:
```python
async def prompt_gen():
    yield {"type": "text", "text": "Your prompt here"}

async for msg in query(prompt=prompt_gen(), options=options):
    ...
```

---

## Changelog Highlights

| Version | Change |
|---------|--------|
| v0.1.37 | Latest release (2026-02-17) |
| v0.1.35 | Pre-previous release (2026-02-13) |
| v0.1.0 | Breaking: `ClaudeCodeOptions` renamed to `ClaudeAgentOptions`; no default system prompt; no filesystem settings loaded by default |

---

**Last verified**: 2026-02-17 | **SDK version**: 0.1.37