---
paths: "**/*agent*.py"
description: Auto-corrections for Claude Agent SDK (Python) v0.1.36
---

# Claude Agent SDK Rules (Python)

## Package
- Package: `claude-agent-sdk` (PyPI, NOT `anthropic-sdk-python`)
- Latest: v0.1.36

## Common Mistakes

### Use async with for ClaudeSDKClient
```python
# WRONG — client won't be properly cleaned up
client = ClaudeSDKClient(options)
result = await client.query("...")

# CORRECT — use async context manager
async with ClaudeSDKClient(options) as client:
    result = await client.query("...")
```

### Use snake_case for options
```python
# WRONG — camelCase from TypeScript
options = ClaudeAgentOptions(
    permissionMode="bypassPermissions",
    maxTurns=10,
    systemPrompt="...",
    allowedTools=["Read"]
)

# CORRECT — Python snake_case
options = ClaudeAgentOptions(
    permission_mode="bypassPermissions",
    max_turns=10,
    system_prompt="...",
    allowed_tools=["Read"]
)
```

### Use @tool decorator for tool definitions
```python
# WRONG — bare function
def get_weather(city: str) -> dict:
    return {"content": [{"type": "text", "text": f"Weather in {city}: sunny"}]}

# CORRECT — use @tool decorator
@tool("get_weather", "Get weather for a city", {"city": {"type": "string"}})
async def get_weather(city: str) -> dict:
    return {"content": [{"type": "text", "text": f"Weather in {city}: sunny"}]}
```

### Import from claude_agent_sdk, not anthropic
```python
# WRONG
from anthropic import ClaudeSDKClient
from anthropic.sdk import query

# CORRECT
from claude_agent_sdk import ClaudeSDKClient, query, tool, create_sdk_mcp_server
```

### Use can_use_tool callback with correct signature
```python
# WRONG — missing updated_input
async def can_use_tool(tool_name, tool_input, options):
    return {"behavior": "allow"}

# CORRECT
async def can_use_tool(tool_name, tool_input, options):
    return {"behavior": "allow", "updated_input": tool_input}
```

### Don't use ANTHROPIC_LOG=debug with SDK
```python
# WRONG — corrupts JSON protocol between SDK and CLI
env={"ANTHROPIC_LOG": "debug"}

# CORRECT — use SDK's built-in debug options
options = ClaudeAgentOptions(debug=True, debug_file="/tmp/agent.log")
```

### Use allowed_tools=None to disable tools, not []
```python
# WRONG — empty list is treated as falsy, all tools enabled
options = ClaudeAgentOptions(allowed_tools=[])

# CORRECT — use None or omit the parameter to get default behavior
options = ClaudeAgentOptions(allowed_tools=None)

# Or explicitly list only the tools you want
options = ClaudeAgentOptions(allowed_tools=["Read", "Grep"])
```
**Why**: Empty list `[]` is falsy in Python, so the `--allowedTools` flag is omitted from the CLI command, making all tools available. Issue [#523](https://github.com/anthropics/claude-agent-sdk-python/issues/523).

### Use thinking config instead of max_thinking_tokens for Opus 4.6+
```python
# WRONG — deprecated, doesn't work with Opus 4.6
options = ClaudeAgentOptions(
    model="claude-opus-4-6",
    max_thinking_tokens=10000
)

# CORRECT — use thinking config with adaptive mode
options = ClaudeAgentOptions(
    model="claude-opus-4-6",
    thinking={"type": "adaptive"},
    effort="high"
)
```
**Why**: Opus 4.6 deprecated `budget_tokens` in favor of adaptive thinking. The `max_thinking_tokens` option maps to the old parameter. Issue [#553](https://github.com/anthropics/claude-agent-sdk-python/issues/553).

### Add explicit prompt for StructuredOutput to avoid wrapper issues
```python
# WRONG — agent may wrap output in {"output": {...}}, breaking validation
options = ClaudeAgentOptions(
    system_prompt="Analyze the data"
)

# CORRECT — add explicit instruction when using StructuredOutput tool
options = ClaudeAgentOptions(
    system_prompt="Analyze the data. **CRITICAL**: When using StructuredOutput tool, provide the JSON object directly - do NOT wrap in {\"output\": {...}}"
)

# BETTER — use output_format instead of relying on StructuredOutput tool
options = ClaudeAgentOptions(
    output_format={"type": "json_schema", "schema": your_schema}
)
```
**Why**: Agent non-deterministically wraps JSON in `{"output": {...}}`, breaking root-level schema validation. Issue [#571](https://github.com/anthropics/claude-agent-sdk-python/issues/571).
