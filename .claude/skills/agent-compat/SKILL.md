---
name: agent-compat
description: Runtime compatibility diff across Claude Code, OpenCode, Codex, and Cursor. Reports gaps and content drift.
argument-hint: "[--axis permissions|model|instructions|hooks|agent-definitions|skills|all] [--scope global|project]"
disable-model-invocation: true
---

# agent-compat

Runtime diff of actual agent configs — no manifest, no second source of truth.

Two parity states:

| State | Meaning |
|---|---|
| GAP | Item present in one agent but not the other |
| DRIFTED | Both have it, content differs |

Dotfiles is canonical — when content drifts, dotfiles version wins.

## SessionStart drift response

When `check-compat-session` hook reports drift at session start:

1. Read drift summary from system-reminder
2. For each GAP: identify which agent config file needs the item, present fix with file path and exact change
3. For each DRIFTED: show `diff` between copies, user decides which version to keep
4. On approval: edit dotfiles config
5. Run `bash agent-compat/scripts/check-compat.sh --axis <affected>` — done when output shows `0 gap(s), 0 warning(s)`

## Empty-extractor discipline

An extractor that returns nothing for an axis (no file-backed surface for
that agent) must carry a comment block with `reason:`, `verified:` date,
and `review-by:` date — same convention as `accepted_gaps` entries in
`descriptors/agents.json`. A bare `return 0` with no explanation is not
acceptable; surfaces get added by vendors, and an unexplained skip never
gets re-examined. `check-compat.sh` warns when an `accepted_gaps` or
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
| skills | skill-name set + symlink target comparison (Claude-visible set is canonical) |

For the skills axis, GAP = skill name missing on one side; DRIFTED = broken
symlink or resolved target differs from Claude's copy. GAP output prints a
ready-to-run `ln -s` command — the checker never writes anything itself
(print-don't-apply). Cursor and Codex have empty skills extractors
(no verified custom-skill surface; see comment blocks for review dates).

## Project scope

`--scope project` runs against the current repo root (override with
`AGENT_COMPAT_PROJECT_DIR`) and checks two axes:

- **instructions** — `AGENTS.md` is canonical. PASS = AGENTS.md exists AND
  either the two names resolve to the same file (symlink in either direction —
  `AGENTS.md -> CLAUDE.md` keeps CLAUDE.md as the real file) or CLAUDE.md
  begins with `@AGENTS.md` (Claude-specific sections may follow; they are
  never diffed). A CLAUDE.md-only repo is a GAP; suggested fix is
  `ln -s CLAUDE.md AGENTS.md` (or the @AGENTS.md split).
- **skills** — every `.claude/skills/<name>` needs a same-named
  `.opencode/skill/<name>` resolving to it; fixes print as `ln -s` commands.

Other axes are global-only and print a skip reason under project scope.
Per-repo accepted gaps live in `<repo>/.agent-compat.json`
(`{"accepted_gaps": {"instructions": [...], "skills": [...]}}`, entries with
`item`/`reason`/`review_by` — same PAST-REVIEW behavior as the global
descriptor; `item: "*"` accepts every item on that axis).

## Usage

```bash
bash agent-compat/scripts/check-compat.sh [--axis permissions|model|instructions|hooks|agent-definitions|skills|all] [--agent opencode|codex|cursor] [--scope global|project]
```

Also runs as install.sh Phase 7 (advisory, never blocks).

## When NOT to use

- Fixing drift directly — edit dotfiles (or run the printed `ln -s`), then run this to verify
- Plugin/marketplace comparison — agent-specific
