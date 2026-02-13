"""Claude Agent SDK query with custom tools."""
import asyncio
from claude_agent_sdk import query, tool, create_sdk_mcp_server, ClaudeAgentOptions

@tool("get_weather", "Get weather for a city", {"city": {"type": "string", "description": "City name"}})
async def get_weather(city: str) -> dict:
    return {"content": [{"type": "text", "text": f"Weather in {city}: 72°F, sunny"}]}

async def main():
    server = create_sdk_mcp_server(name="weather", tools=[get_weather])

    options = ClaudeAgentOptions(
        mcp_servers={"weather": server},
        permission_mode="bypassPermissions",
        allow_dangerously_skip_permissions=True,
        max_turns=10,
    )

    async for message in query(prompt="What's the weather in Tokyo?", options=options):
        if message["type"] == "result" and message["subtype"] == "success":
            print(message["result"])

asyncio.run(main())
