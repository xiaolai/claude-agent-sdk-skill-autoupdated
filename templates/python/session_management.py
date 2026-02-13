"""Session management with Claude Agent SDK."""
import asyncio
from claude_agent_sdk import query, ClaudeAgentOptions

async def main():
    # First query — capture session ID
    session_id = None
    options = ClaudeAgentOptions(
        max_turns=5,
        permission_mode="bypassPermissions",
        allow_dangerously_skip_permissions=True,
    )

    async for msg in query(prompt="Read the README.md file", options=options):
        if msg["type"] == "system" and msg.get("subtype") == "init":
            session_id = msg["session_id"]
        if msg["type"] == "result" and msg["subtype"] == "success":
            print(f"First query done. Session: {session_id}")

    if not session_id:
        print("No session ID captured")
        return

    # Resume session
    resume_options = ClaudeAgentOptions(
        resume=session_id,
        max_turns=5,
        permission_mode="bypassPermissions",
        allow_dangerously_skip_permissions=True,
    )

    async for msg in query(prompt="Now summarize what you read", options=resume_options):
        if msg["type"] == "result" and msg["subtype"] == "success":
            print(f"Resume result: {msg['result'][:200]}")

    # Fork session
    fork_options = ClaudeAgentOptions(
        resume=session_id,
        fork_session=True,
        max_turns=5,
        permission_mode="bypassPermissions",
        allow_dangerously_skip_permissions=True,
    )

    async for msg in query(prompt="Try a different approach", options=fork_options):
        if msg["type"] == "result" and msg["subtype"] == "success":
            print(f"Fork result: {msg['result'][:200]}")

asyncio.run(main())
