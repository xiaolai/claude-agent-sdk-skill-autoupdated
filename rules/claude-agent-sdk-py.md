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
