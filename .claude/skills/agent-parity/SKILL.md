---
name: agent-parity
description: Runtime parity diff across Claude Code, OpenCode, Codex, and Cursor. Reports gaps and content drift.
argument-hint: "[--axis permissions|model|instructions|hooks|agent-definitions|all]"
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

## Empty-extractor discipline

An extractor that returns nothing for an axis (no file-backed surface for
that agent) must carry a comment block with `reason:`, `verified:` date,
and `review-by:` date — same convention as `accepted_gaps` entries in
`descriptors/agents.json`. A bare `return 0` with no explanation is not
acceptable; surfaces get added by vendors, and an unexplained skip never
gets re-examined. `check-parity.sh` warns when an `accepted_gaps` or
`accepted_model_reason` entry's `review_by` date is in the past
(`PAST-REVIEW` line); empty-extractor comment dates are not machine-checked
but follow the same review cadence.

## Axes

| Axis | Diff method |
|---|---|
| permissions | deny pattern set comparison |
| model | base model ID match |
| instructions | doc filename + content diff |
| hooks | hook intent name comparison |
| agent-definitions | scan/execute/decide agent availability |

## Usage

```bash
bash agent-parity/scripts/check-parity.sh [--axis permissions|model|instructions|hooks|agent-definitions|all] [--agent opencode|codex|cursor]
```

Also runs as install.sh Phase 7 (advisory, never blocks).

## When NOT to use

- Fixing drift directly — edit dotfiles, then run this to verify
- Project-level settings — global only
- Plugin/marketplace comparison — agent-specific
