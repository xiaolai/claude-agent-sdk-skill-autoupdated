# Changelog

## 2026-04-08

- SDK TS v0.2.92 → v0.2.96; PY v0.1.56 unchanged
- TS: thinking `display` option added, `apiProvider: 'mantle'` documented; SKILL-typescript.md updated to v0.2.96
- PY: Added KI #40 (`setting_sources=[]` silently ignored), KI #41 (`ThinkingBlock` missing `signature` crash); updated KI #23 for merged thinking-flags PR #796
- Typecheck false-positive (recurring stale-comma artifact); mended + verify passed 18/18 on attempt 2
- [Full report](reports/2026-04-08.md)

## 2026-04-07

- Research only, no version change (TS v0.2.92, PY v0.1.56 unchanged); GitHub API unavailable
- PY audit: verified all 39 ClaudeAgentOptions fields, 10 hook events, all message/client/MCP types match SKILL-python.md; updated "Last verified" date
- TS audit: skipped (version unchanged); Part C consistency checks passed (27 HOOK_EVENTS, KI #1–#49 sequential)
- Typecheck false-positive (recurring stale-comma import artifact)
- [Full report](reports/2026-04-07.md)

## 2026-04-06

- Research only, no version change (TS v0.2.92, PY v0.1.56 unchanged); GitHub API unavailable
- TS audit: added `terminal_reason?: TerminalReason`, `deferred_tool_use?: SDKDeferredToolUse` to SDKResultMessage; documented full TerminalReason union (13 values)
- Typecheck false-positive (recurring stale-comma import artifact); pipeline outcomes recorded as success
- [Full report](reports/2026-04-06.md)

## 2026-04-05

- Research only, no version change (TS v0.2.92, PY v0.1.56 unchanged); GitHub API unavailable
- Doc fix: added missing `includeSystemMessages` field to `getSessionMessages()` in SKILL-typescript.md
- PY audit: corrected stale `lastAuditedVersion` 0.1.52 → 0.1.56; all templates verified clean
- [Full report](reports/2026-04-05.md)

## 2026-04-04

- SDK v0.2.91 → v0.2.92 (TypeScript); Python v0.1.55 → v0.1.56
- No new Known Issues added; research found no new actionable issues (TS above #236, PY above #776)
- Typecheck false-positive (recurring stale-comma import artifact); verify passed 28/28 after 1 mending run
- [Full report](reports/2026-04-04.md)

## 2026-04-03

- SDK v0.2.90 → v0.2.91 (TypeScript); Python v0.1.54 → v0.1.55
- No new Known Issues added; research found no new actionable issues (TS above #236, PY above #776)
- Typecheck false-positive (recurring stale-comma import artifact); verify passed 28/28 after 1 mending run
- [Full report](reports/2026-04-03.md)

## 2026-04-02

- SDK v0.2.89 → v0.2.90 (TypeScript); Python v0.1.53 → v0.1.54
- No new Known Issues added; research found no new actionable issues (TS above #236, PY above #776)
- Typecheck false-positive (recurring stale-comma import artifact); verify passed 28/28 after 1 mending run
- [Full report](reports/2026-04-02.md)

## 2026-04-01

- SDK v0.2.88 → v0.2.89 (TypeScript); Python v0.1.53 unchanged
- No new Known Issues added; research found no new actionable issues above TS #236 / PY #776
- Typecheck false-positive (recurring stale-comma import artifact); verify passed 18/18 after 1 mending run
- [Full report](reports/2026-04-01.md)

## 2026-03-30

- No version changes (TS v0.2.87, PY v0.1.52 unchanged); research-only run
- Python research added KI #35 (connect() prompt silent drop, fixed v0.1.52) and KI #36 (ExitPlanMode terminates SDK turn); updated @tool Annotated docs for v0.1.52
- Typecheck false-positive (recurring script-generated malformed import string)
- [Full report](reports/2026-03-30.md)

## 2026-03-29

- SDK v0.2.86 → v0.2.87 (TypeScript); Python v0.1.51 → v0.1.52
- No new Known Issues added; research found no new issues above TS #236 / PY #713
- Typecheck false-positive (recurring stale-comma artifact); verify passed 28/28 after 1 mending run
- [Full report](reports/2026-03-29.md)

## 2026-03-28

- SDK v0.2.85 → v0.2.86 (TypeScript); Python v0.1.50 → v0.1.51
- No new Known Issues added (no new bug issues detected in change report)
- Verify failed (false positives: stale-version regex matches historical changelog/workaround references); typecheck soft-failed (script-generated malformed import string)
- [Full report](reports/2026-03-28.md)

## 2026-03-27

- SDK v0.2.84 → v0.2.85 (TypeScript); Python v0.1.50 unchanged
- New: `taskBudget` option (@alpha), `reloadPlugins()`/`seedReadState()` query methods, `TaskCreated` hook event (26 total hooks)
- Typecheck false-positive (recurring stale-comma artifact); verify passed 18/18 after 2 mending runs
- [Full report](reports/2026-03-27.md)

## 2026-03-26

- SDK v0.2.83 → v0.2.84 (TypeScript); Python v0.1.50 unchanged
- TS: Added 3 new Known Issues (#42 sandbox silent degradation, #43 Zod v4 `.describe()` drop, #44 ExitWorktree state lost across queries)
- PY: Added 3 new Known Issues (#30–#32); updated KI #10, #11, #29 with pending fix status (5 PRs merged 2026-03-25/26, not yet released)
- [Full report](reports/2026-03-26.md)

## 2026-03-25

- SDK v0.2.81 → v0.2.83 (TypeScript); Python v0.1.50 unchanged
- New: `SDKSessionStateChangedMessage`, `CwdChanged`/`FileChanged` hooks, `AgentDefinition.initialPrompt`, `SandboxSettings.failIfUnavailable`, `decisionClassification` on `PermissionResult`
- Typecheck false-positive recurring (stray-comma artifact, non-blocking); verify passed 18/18 checks
- [Full report](reports/2026-03-25.md)

## 2026-03-24

- Research only, no version change (TS v0.2.81, Python v0.1.50 unchanged)
- Both research agents verified skill docs and updated "Last verified" dates; GitHub API unavailable, no new issue scanning
- No new Known Issues added (TS: 41 total, PY: 29 total)
- Typecheck false-positive recurring (stray-comma artifact, non-blocking)
- [Full report](reports/2026-03-24.md)

## 2026-03-23

- Research only, no version change (TS v0.2.81, Python v0.1.50 unchanged)
- PY: Added KI #29 — SDK MCP Server tool errors not propagated (`isError`/`is_error` camelCase mismatch); 8 issues evaluated
- TS: Added missing `SessionStart.hookSpecificOutput.initialUserMessage` example; GitHub API unavailable, no issue scan
- Typecheck false-positive recurring (stray-comma artifact, non-blocking)
- [Full report](reports/2026-03-23.md)

## 2026-03-22

- Research only, no version change (TS v0.2.81, Python v0.1.50 unchanged)
- TS: corrected verdicts for 4 tracked issues (#230, #231, #236, #117); GitHub API unavailable, no new issues scanned
- PY: documented 6 undocumented MCP status types in SKILL-python.md (McpStatusResponse, McpServerStatus, etc.)
- Typecheck false-positive recurring (stray-comma artifact, non-blocking)
- [Full report](reports/2026-03-22.md)

## 2026-03-21

- SDK TS v0.2.80 → v0.2.81; Python v0.1.49 → v0.1.50 (both bumped)
- Typecheck false-positive (recurring stray-comma in import-check script); fixed by mending agent, verify passed on attempt 2
- Research: no new known issues added today
- [Full report](reports/2026-03-21.md)

## 2026-03-20

- SDK TS v0.2.79 → v0.2.80; Python v0.1.49 unchanged
- Typecheck false-positive (stray comma in import-check script); fixed by mending agent, verify passed on attempt 2
- Research: TS scanned new issues (#230–#236, #117); PY no new findings
- [Full report](reports/2026-03-20.md)

## 2026-03-19

- SDK TS v0.2.77 → v0.2.79; Python v0.1.49 unchanged
- TS: documented new `StopFailure` hook event (23rd hook); cleaned up KI #35 fix-version note; cross-referenced issues #230, #231, #236, #117
- PY: added KI #28 (`DEBUG` env var corrupts JSON in Docker/Linux); updated KI #23 with pending fix PR #699
- Verify passed on attempt 2 (1 mending run); typecheck false-positive (recurring, non-blocking)
- [Full report](reports/2026-03-19.md)

## 2026-03-18

- Research only, no version change (TS v0.2.77, Python v0.1.49 unchanged)
- TS: added KI #40 (file checkpointing no-op in SDK mode), KI #41 (subagents hardcoded to deny `bypassPermissions`)
- PY: added KI #23 (thinking=disabled breaks compatible providers), KI #24 (MCP tool calls fail after ~70s), KI #25 (output_format+resume broken), KI #26 (v0.1.49 incomplete PyPI wheels — Linux/Windows blocked), KI #27 (can_use_tool never fires — critical security no-op); new auto-correction rule for can_use_tool
- Typecheck false-positive (recurring script artifact, non-blocking)
- [Full report](reports/2026-03-18.md)

## 2026-03-17

- SDK TS v0.2.76 → v0.2.77; Python v0.1.48 → v0.1.49 (both bumped)
- TS v0.2.77: new `SDKAPIRetryMessage` (23rd type), `applyFlagSettings()`, `AccountInfo.apiProvider`, richer `CanUseTool` fields (`title`, `displayName`, `description`), new `'compact'` InstructionsLoaded load_reason
- Research: tracked 2 new TS issues (#230, #231, pending KI assignment); PY no new findings
- [Full report](reports/2026-03-17.md)

## 2026-03-16

- Research only, no version change (TS v0.2.76, Python v0.1.48 unchanged)
- TS: added `tagSession()` docs to SKILL-typescript.md (was exported but undocumented); updated BaseHookInput to include `agent_id?` / `agent_type?`; GitHub API unavailable, no new issues scanned
- PY: consistency audit passed (no changes); GH_TOKEN unavailable for issue scan
- Typecheck false-positive (recurring script artifact, non-blocking)
- [Full report](reports/2026-03-16.md)

## 2026-03-15

- Research only, no version change (TS v0.2.76, Python v0.1.48 unchanged)
- TS: added KI #37 (fast mode requires Bun binary, unavailable in Node.js), KI #38 (MCP zombie processes after session ends); updated KI #35 (sdk-tools export fixed in v0.2.76)
- PY: no new findings — version unchanged, GH_TOKEN unavailable for issue scan
- Typecheck false-positive (recurring script artifact, non-blocking)
- [Full report](reports/2026-03-15.md)

## 2026-03-14

- SDK TS v0.2.74 → v0.2.76; Python v0.1.48 unchanged
- Added `getSessionInfo()`, `forkSession()` APIs; `listSessions()` pagination (`offset`); `SDKSessionInfo` gains `tag`, `createdAt` fields; hook count 21 → 22
- Research agents found no new issues (all issues already current through TS #229, PY #672)
- [Full report](reports/2026-03-14.md)

## 2026-03-13

- Research only, no version change (TS v0.2.74, Python v0.1.48)
- PY: documented 3 hook output types (`PreToolUseHookSpecificOutput`, `PostToolUseHookSpecificOutput`, `UserPromptSubmitHookSpecificOutput`)
- TS: full API audit confirmed consistent; last-verified date updated
- Typecheck false-positive (recurring script artifact, non-blocking)
- [Full report](reports/2026-03-13.md)

## 2026-03-12

- SDK TS v0.2.72 → v0.2.74; Python v0.1.48 unchanged; verify passed (18/18, 1 mending run)
- TS: documented `renameSession()`, `agentProgressSummaries` option, `supportsAutoMode` model field
- PY: added KI #22 (early async generator exit poisons event loop); revised KI #2 (`allowed_tools` vs `tools` semantics); updated KI #14, #16, #17, #20
- Typecheck false-positive (recurring script artifact, non-blocking)
- [Full report](reports/2026-03-12.md)

## 2026-03-11

- Research only, no version change (TS v0.2.72, Python v0.1.48)
- TS: added KI #36 (settings.json env overrides options.env); changelog entries for v0.2.71 and v0.2.72
- PY: added KI #20 (multi-user session confusion) and KI #21 (include_partial_messages breaks Bedrock/Vertex); updated KI #14, #16, #17, #19
- Typecheck false-positive (recurring script artifact, non-blocking)
- [Full report](reports/2026-03-11.md)

## 2026-03-10

- SDK TS v0.2.71 → v0.2.72; Python v0.1.48 unchanged; verify passed (18/18, no mending)
- Python: added KI #18 (global settings override) and KI #19 (dict as options raises AttributeError); updated KI #16 and #17
- Typecheck false-positive (recurring script artifact, non-blocking)
- [Full report](reports/2026-03-10.md)

## 2026-03-09

- Research only, no version change (TS v0.2.71, Python v0.1.48)
- TS: added `prompt` field to `task_started` message subtype docs; PY: full API surface verified, no changes
- Typecheck step false-positive (script artifact, non-blocking); same issue as 2026-03-08
- [Full report](reports/2026-03-09.md)

## 2026-03-08

- Research only, no version change (TS v0.2.71, Python v0.1.48)
- Python: added subagent attribution docs, McpSdkServerConfigStatus/McpClaudeAIProxyServerConfig types, and TypedDict dot-notation rule (issue #623)
- Typecheck step false-positive (script artifact, non-blocking)
- [Full report](reports/2026-03-08.md)

## 2026-03-06

- SDK TS v0.2.69 → v0.2.70, Python v0.1.46 → v0.1.47; verify passed (28/28 checks, no mending)
- No new known issues added; typecheck step had a false-positive script error (not a template bug)
- [Full report](reports/2026-03-06.md)

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
