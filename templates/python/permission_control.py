"""Custom permission control with Claude Agent SDK."""
import asyncio
from claude_agent_sdk import query, ClaudeAgentOptions, HookMatcher, HookContext

# NOTE: Use PreToolUse hooks for permission enforcement (recommended approach).
# can_use_tool callbacks require AsyncIterable prompts (raises ValueError with
# string prompts since v0.1.78+), and may not fire reliably — see KI #27.

async def permission_hook(
    input_data: dict, tool_use_id: str | None, context: HookContext
) -> dict:
    """Block dangerous operations using a PreToolUse hook."""
    tool_name = input_data.get("tool_name", "")
    tool_input = input_data.get("tool_input", {})

    # Allow read-only tools immediately
    if tool_name in ["Read", "Grep", "Glob"]:
        return {}

    # Block destructive bash commands
    if tool_name == "Bash":
        dangerous_patterns = ["rm -rf", "dd if=", "mkfs"]
        command = tool_input.get("command", "")
        if any(p in command for p in dangerous_patterns):
            return {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": "Destructive command blocked",
                }
            }

    # Allow everything else
    return {}

async def main():
    from claude_agent_sdk import ResultMessage

    options = ClaudeAgentOptions(
        hooks={"PreToolUse": [HookMatcher(hooks=[permission_hook])]},
        permission_mode="default",
        max_turns=10,
    )

    async for msg in query(prompt="List files in the current directory", options=options):
        if isinstance(msg, ResultMessage) and msg.subtype == "success":
            print(msg.result)

asyncio.run(main())
