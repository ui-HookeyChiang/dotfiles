---
name: agent-parity
description: Runtime parity diff across Claude Code and OpenCode. Reports gaps and content drift.
argument-hint: "[--axis permissions|model|instructions|hooks|all]"
disable-model-invocation: true
---

# agent-parity

Runtime diff of actual agent configs — no manifest, no second source of truth.

Two parity states:

| State | Meaning |
|---|---|
| GAP | Item present in one agent but not the other |
| DRIFTED | Both have it, content differs |

Dotfiles is canonical — when content drifts, dotfiles version wins.

## SessionStart drift response

When `check-parity-session` hook reports drift at session start:

1. Read drift summary from system-reminder
2. For each GAP: identify which agent config file needs the item, present fix with file path and exact change
3. For each DRIFTED: show `diff` between copies, user decides which version to keep
4. On approval: edit dotfiles config
5. Run `bash agent-parity/scripts/check-parity.sh --axis <affected>` — done when output shows `0 gap(s), 0 warning(s)`

## Axes

| Axis | Diff method |
|---|---|
| permissions | deny pattern set comparison |
| model | base model ID match |
| instructions | doc filename + content diff |
| hooks | hook intent name comparison |

## Usage

```bash
bash agent-parity/scripts/check-parity.sh [--axis permissions|model|instructions|hooks|all]
```

Also runs as install.sh Phase 7 (advisory, never blocks).

## When NOT to use

- Fixing drift directly — edit dotfiles, then run this to verify
- Project-level settings — global only
- Plugin/marketplace comparison — agent-specific
