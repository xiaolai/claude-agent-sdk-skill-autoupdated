"""Basic Claude Agent SDK query example."""
import asyncio
from claude_agent_sdk import query, ClaudeAgentOptions

async def main():
    options = ClaudeAgentOptions(
        system_prompt="You are a helpful assistant.",
        max_turns=5,
        permission_mode="bypassPermissions",
        allow_dangerously_skip_permissions=True,
    )

    async for message in query(prompt="What is 2 + 2?", options=options):
        if message["type"] == "assistant":
            print(message["message"])
        elif message["type"] == "result":
            if message["subtype"] == "success":
                print(f"Result: {message['result']}")
                print(f"Cost: ${message.get('total_cost_usd', 0):.4f}")
            else:
                print(f"Error: {message.get('errors', [])}")

asyncio.run(main())
