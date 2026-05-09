"""Multi-agent workflow with custom MCP tools (Python)."""
import asyncio
from typing import Any
from claude_agent_sdk import (
    query, ClaudeAgentOptions, AgentDefinition, create_sdk_mcp_server, tool,
    AssistantMessage, ResultMessage, TextBlock, HookMatcher, HookContext,
)


@tool("send_notification", "Send notification to a team", {"message": str, "priority": str})
async def send_notification(args: dict[str, Any]) -> dict[str, Any]:
    priority = args.get("priority", "medium")
    return {"content": [{"type": "text", "text": f"Sent ({priority}): {args['message']}"}]}


@tool("check_health", "Check service health", {"service": str})
async def check_health(args: dict[str, Any]) -> dict[str, Any]:
    return {
        "content": [
            {"type": "text", "text": f'{{"service": "{args["service"]}", "status": "healthy"}}'}
        ]
    }


app_tools = create_sdk_mcp_server(
    name="app-services",
    version="1.0.0",
    tools=[send_notification, check_health],
)


async def safety_hook(
    input_data: dict, tool_use_id: str | None, context: HookContext
) -> dict:
    """Block destructive commands via PreToolUse hook.

    NOTE: Use PreToolUse hooks instead of can_use_tool — hooks work with string
    prompts and are the recommended permission enforcement mechanism (KI #27).
    """
    if input_data.get("tool_name") == "Bash":
        dangerous = ["rm -rf", "dd if=", "mkfs", "shutdown"]
        command = input_data.get("tool_input", {}).get("command", "")
        if any(p in command for p in dangerous):
            return {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": f"Blocked: {command}",
                }
            }
    return {}


async def main():
    options = ClaudeAgentOptions(
        system_prompt="You are a DevOps orchestrator. Coordinate agents to complete tasks safely.",
        mcp_servers={"app-services": app_tools},
        agents={
            "deployer": AgentDefinition(
                description="Handles deployments and rollbacks",
                prompt="You deploy applications. Always verify health after deployment.",
                tools=["Bash", "Read", "mcp__app-services__check_health", "mcp__app-services__send_notification"],
                model="sonnet",
            ),
            "security-checker": AgentDefinition(
                description="Security audits and vulnerability scanning",
                prompt="Scan for exposed secrets, outdated deps, and OWASP issues.",
                tools=["Read", "Grep", "Bash"],
                model="sonnet",
            ),
            "monitor": AgentDefinition(
                description="System monitoring and alerting",
                prompt="Check metrics, error rates, and system health.",
                tools=["Bash", "Read", "mcp__app-services__check_health"],
                model="haiku",
            ),
        },
        allowed_tools=[
            "Task", "Read", "Bash", "Grep",
            "mcp__app-services__send_notification",
            "mcp__app-services__check_health",
        ],
        hooks={"PreToolUse": [HookMatcher(hooks=[safety_hook])]},
        permission_mode="bypassPermissions",
    )

    async for msg in query(
        prompt="Deploy v2.5.0 with security check and health monitoring",
        options=options,
    ):
        if isinstance(msg, AssistantMessage):
            for block in msg.content:
                if isinstance(block, TextBlock):
                    print(block.text)
        elif isinstance(msg, ResultMessage):
            if msg.subtype == "success":
                print(f"\nDone: {msg.result}")
                print(f"Cost: ${msg.total_cost_usd or 0:.4f}")
            else:
                print(f"Error: {msg.subtype}")


asyncio.run(main())
