---
paths: "**/*agent*.ts"
description: Auto-corrections for Claude Agent SDK v0.2.37
---

# Claude Agent SDK Rules

## Package
- Package: `@anthropic-ai/claude-agent-sdk` (NOT `@anthropic-ai/claude-code`)
- Latest: v0.2.37

## Common Mistakes

### Hooks are callback matchers, not direct functions
```typescript
// WRONG
hooks: { PreToolUse: async (input) => { ... } }

// CORRECT
hooks: { PreToolUse: [{ matcher: 'Bash', hooks: [myCallback] }] }
```

### canUseTool returns PermissionResult, not simple objects
```typescript
// WRONG
canUseTool: async (tool, input) => ({ behavior: "allow" })

// CORRECT
canUseTool: async (tool, input, { signal }) => ({
  behavior: "allow", updatedInput: input
})
```

### Structured outputs use outputFormat.schema directly
```typescript
// WRONG (old pattern)
outputFormat: { type: "json_schema", json_schema: { name: "...", strict: true, schema: ... } }

// CORRECT
outputFormat: { type: "json_schema", schema: myJsonSchema }
```

### Zod schema conversion
```typescript
// WRONG (old library)
import { zodToJsonSchema } from "zod-to-json-schema";

// CORRECT (built-in Zod v3.24.1+ / v4+)
const jsonSchema = z.toJSONSchema(myZodSchema);
```

### URL-based MCP servers require type field
```typescript
// WRONG — causes cryptic "exit code 1"
mcpServers: { api: { url: "https://example.com/mcp" } }

// CORRECT
mcpServers: { api: { type: "http", url: "https://example.com/mcp" } }
```

### No default system prompt or settings
```typescript
// SDK v0.1.0+ defaults: no system prompt, no filesystem settings
// Add explicitly if needed:
systemPrompt: { type: 'preset', preset: 'claude_code' },
settingSources: ['project']
```

### Subagents require Task in allowedTools
```typescript
// WRONG — subagents won't be invocable
allowedTools: ["Read", "Write"],
agents: { reviewer: { ... } }

// CORRECT
allowedTools: ["Read", "Write", "Task"],
agents: { reviewer: { ... } }
```

### allowedTools doesn't work with bypassPermissions mode
```typescript
// WRONG — allowedTools is ignored, Claude can still use Edit/Write/Bash
options: {
  allowedTools: ["Read", "Glob", "Grep"],
  permissionMode: "bypassPermissions",
  allowDangerouslySkipPermissions: true
}

// CORRECT — use default or acceptEdits mode for allowedTools to work
options: {
  allowedTools: ["Read", "Glob", "Grep"],
  permissionMode: "default"
}
```
