"""Error handling patterns with Claude Agent SDK."""
import asyncio
from claude_agent_sdk import query, ClaudeAgentOptions

async def main():
    options = ClaudeAgentOptions(
        max_turns=5,
        max_budget_usd=1.00,
        permission_mode="bypassPermissions",
        allow_dangerously_skip_permissions=True,
    )

    session_id = None
    async for msg in query(prompt="Analyze this codebase", options=options):
        match msg["type"]:
            case "system":
                if msg.get("subtype") == "init":
                    session_id = msg["session_id"]
                    print(f"Session: {session_id}")
            case "result":
                match msg["subtype"]:
                    case "success":
                        print(f"Done: {msg['result'][:200]}")
                        print(f"Cost: ${msg.get('total_cost_usd', 0):.4f}")
                    case "error_max_turns":
                        print("Hit max turns limit")
                    case "error_max_budget_usd":
                        print("Hit budget limit")
                    case "error_during_execution":
                        print(f"Errors: {msg.get('errors', [])}")

asyncio.run(main())
