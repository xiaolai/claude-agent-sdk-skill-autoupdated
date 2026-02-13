"""In-process MCP server with Claude Agent SDK."""
import asyncio
from claude_agent_sdk import query, tool, create_sdk_mcp_server, ClaudeAgentOptions

@tool("search_docs", "Search documentation", {
    "query": {"type": "string", "description": "Search query"},
    "limit": {"type": "integer", "description": "Max results", "default": 5}
})
async def search_docs(query: str, limit: int = 5) -> dict:
    results = [f"Result {i}: {query} match" for i in range(1, min(limit + 1, 4))]
    return {"content": [{"type": "text", "text": "\n".join(results)}]}

@tool("get_doc", "Get a specific document", {
    "doc_id": {"type": "string", "description": "Document ID"}
})
async def get_doc(doc_id: str) -> dict:
    return {"content": [{"type": "text", "text": f"Document {doc_id}: Lorem ipsum..."}]}

async def main():
    server = create_sdk_mcp_server(
        name="docs",
        version="1.0.0",
        tools=[search_docs, get_doc],
    )

    options = ClaudeAgentOptions(
        mcp_servers={"docs": server},
        system_prompt="You help users search documentation.",
        permission_mode="bypassPermissions",
        allow_dangerously_skip_permissions=True,
    )

    async for msg in query(prompt="Search for authentication docs", options=options):
        if msg["type"] == "result" and msg["subtype"] == "success":
            print(msg["result"])

asyncio.run(main())
