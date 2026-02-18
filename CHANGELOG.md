# Changelog

## 2026-02-18

- SDK TS v0.2.44 → v0.2.45; verify passed after 2 mending runs (attempt 3 of 3)
- API docs updated: 2 new message types (task_started, RateLimitEvent), hook types fully typed, tool_progress field renamed elapsed_ms→elapsed_time_seconds
- Python: transport param added to query(), rewind_files() param renamed, output_format type corrected
- [Full report](reports/2026-02-18.md)

## 2026-02-17

- SDK v0.2.42 → v0.2.44 (TypeScript) and v0.1.36 → v0.1.37 (Python), verify passed after 1 mending run
- TypeScript: `canUseTool` API expanded with `toolUseID`, `agentID`, `blockedPath`, `decisionReason` fields
- Python: Known Issue #9 fix version corrected to v0.1.37; hook events count updated (6→10)
- [Full report](reports/2026-02-17.md)

## 2026-02-16

- Research only, no version change (TypeScript v0.2.42, Python v0.1.36)
- Python SDK: Added 5 new known issues (#10–#14), updated #3 with v0.1.35 fix
- Key additions: CLAUDECODE=1 env inheritance, search_result blocks dropped, FastAPI hanging, session fork failure, SDK MCP string prompts crash
- [Full report](reports/2026-02-16.md)

## 2026-02-15

- Research only, no version change (TypeScript v0.2.42, Python v0.1.36)
- Added 1 TypeScript rule for tool() API (requires ZodRawShape, not ZodObject)
- State maintenance: synced GitHub release tags
- [Full report](reports/2026-02-15.md)

## 2026-02-14

- Research only, no version change (TypeScript v0.2.42, Python v0.1.36)
- Python SDK: Added 9 known issues (#1–#9), applied 5 template fixes
- Key additions: Query.close() hang fix, FastAPI compatibility issue, allowed_tools=[] pitfall
- [Full report](reports/2026-02-14.md)

## 2026-02-13

- SDK v0.2.39 → v0.2.41 (verification failed on stale version in historical report)
- Added Known Issue #20 (Zod structured output requires draft-07 target)
- [Full report](reports/2026-02-13.md)

## 2026-02-12

- Research only, no version change
- Added 2 known issues (#18: v2 sessions don't support plugins, #19: subagent tool restrictions not enforced)
- [Full report](reports/2026-02-12.md)

## 2026-02-11

- Research only, no version change
- Added 6 known issues (#12–#17); evaluated 13 issues total
- [Full report](reports/2026-02-11.md)

## 2026-02-09

- Research only, no version change (SDK remains at v0.2.37)
- Added 6 known issues, 1 usage rule; evaluated 13 issues total
- [Full report](reports/2026-02-09.md)
