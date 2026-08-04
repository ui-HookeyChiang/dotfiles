# OpenCode Hook Bridge

This directory contains the OpenCode plugin implementation (`skill-dev-hooks.ts`) that bridges skill-dev's hook policies to OpenCode CLI.

## Overview

The OpenCode plugin executes Claude's hook infrastructure within OpenCode's agent sandbox. It synthesizes tool-use events into JSON payloads, shells out to bash hooks, and raises permission denials when hooks reject a tool use.

## Plugin Entry Point

- `skill-dev-hooks.ts` — OpenCode Plugin that intercepts:
  - `chat.message` (agent-map writer)
  - `tool.execute.before` (hook enforcement for Edit, Write, Bash)

## Manifest Agreement

The `hooks/manifest.json` declares hooks via the `externalHook` field under `harnesses.opencode`:

```json
{
  "name": "block-bare-read",
  "harnesses": {
    "opencode": {
      "externalHook": "block-bare-read"
    }
  }
}
```

The `externalHook` string refers to a bash script under `hooks/` (e.g., `block-bare-read.sh`) that the plugin will invoke. The test `hooks/tests/test-opencode-manifest-agreement.sh` verifies that all declared `externalHook` entries match scripts referenced in the plugin code.

### Current Manifest Entries

| Hook Name | Bash Script | Purpose |
|-----------|------------|---------|
| `block-main-edit` | `block-main-edit.sh` | Deny Edit/Write on main worktree |
| `guard-stale-base` | `guard-stale-base.sh` | Block branching from stale local refs |
| `guard-agent-worktree-files` | `guard-agent-worktree.sh` | Subagent file isolation |
| `block-bare-read` | `block-bare-read.sh` | Block shell-exploration commands |

## Payload Synthesis

The plugin constructs JSON payloads for hooks in the format:

```typescript
// For Bash commands
{
  tool_input: { command: string }
}

// For file operations
{
  tool_input: { file_path: string }
}
```

This matches the input format that bash hooks expect (via `jq .tool_input.command` etc.).

## Hook Response Format

Hooks emit JSON with a `hookSpecificOutput` structure:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow" | "deny",
    "permissionDecisionReason": "optional explanation"
  }
}
```

If `permissionDecision` is `"deny"`, the plugin raises an error with the reason.

## Testing

Run the test suite to verify plugin ↔ manifest agreement and payload behavior:

```bash
# Verify manifest entry ↔ plugin hook agreement
bash hooks/tests/test-opencode-manifest-agreement.sh

# Verify payload synthesis and hook behavior for block-bare-read
bash hooks/tests/test-opencode-bridge-payload.sh

# Run all tests
for test in hooks/tests/test-*.sh; do bash "$test"; done
```

## Known Limitation: .gitignore Gap

Native `grep` (e.g., `rg pattern .`) does not respect `.gitignore` and will scan ignored paths (vendor/, node_modules/, etc.). The hook blocks bare `grep` and `rg` to encourage use of the Grep tool.

**Escape hatch:** If you need to search ignored paths with native grep, set `ALLOW_BARE_READ=1`:

```bash
ALLOW_BARE_READ=1 rg --no-ignore pattern src/
```

This is a deliberate tradeoff: the hook prioritizes discovery ("use the Grep tool") over permissive shell access. For reproducible, performant search across large codebases with many ignored paths, use the Grep tool which respects `.gitignore` by default.
