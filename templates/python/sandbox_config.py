"""Sandbox configuration with Claude Agent SDK."""
import asyncio
from claude_agent_sdk import query, ClaudeAgentOptions, ResultMessage


async def basic_sandbox():
    """Basic sandbox — auto-approve bash, allow local network."""
    options = ClaudeAgentOptions(
        permission_mode="bypassPermissions",
        allow_dangerously_skip_permissions=True,
        sandbox={
            "enabled": True,
            "autoAllowBashIfSandboxed": True,
            "network": {"allowLocalBinding": True},
        },
    )

    async for msg in query(prompt="Build the project and run tests", options=options):
        if isinstance(msg, ResultMessage):
            if msg.subtype == "success":
                print(msg.result)
            else:
                print(f"Error: {msg.subtype}")


async def production_sandbox():
    """Production sandbox — restricted network, canUseTool for escape hatch."""

    async def can_use_tool(tool_name: str, tool_input: dict, options: dict) -> dict:
        # Approve or deny unsandboxed command requests
        if tool_name == "Bash" and tool_input.get("dangerouslyDisableSandbox"):
            safe_commands = ["npm publish", "docker push"]
            if any(tool_input.get("command", "").startswith(cmd) for cmd in safe_commands):
                return {"behavior": "allow", "updated_input": tool_input}
            return {"behavior": "deny", "message": f"Unsandboxed blocked: {tool_input.get('command')}"}
        return {"behavior": "allow", "updated_input": tool_input}

    options = ClaudeAgentOptions(
        can_use_tool=can_use_tool,
        sandbox={
            "enabled": True,
            "autoAllowBashIfSandboxed": True,
            # Static allowlist: always bypass sandbox
            "excludedCommands": ["git", "docker", "kubectl"],
            # Model can request unsandboxed execution — falls back to can_use_tool
            "allowUnsandboxedCommands": True,
            "network": {
                "allowLocalBinding": True,
                "allowedDomains": ["api.github.com", "registry.npmjs.org"],
                "allowManagedDomainsOnly": True,
            },
        },
    )

    async for msg in query(prompt="Deploy and verify health checks", options=options):
        if isinstance(msg, ResultMessage) and msg.subtype == "success":
            print(msg.result)


asyncio.run(basic_sandbox())
