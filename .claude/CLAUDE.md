# Routing — one map, idea → ship

Match the raw input to a route. First match wins.

| Raw input                   | Route                                    | Then           |
|-----------------------------|------------------------------------------|----------------|
| fuzzy intent / feature      | `flow` (Converge = `grill-with-docs`)    | → spec         |
| missing facts               | `research` → `grill-with-docs`           | → spec         |
| unfelt design question      | `prototype` → `grill-with-docs`          | → spec         |
| issue pile (not yours)      | `triage`                                 | → `flow-dev`   |
| something broken            | `diagnosing-bugs`                        | → fix          |
| codebase drift              | `improve-codebase-architecture`          | → re-grill     |
| multi-session build         | `to-spec` → `to-tickets` → `flow-dev`    | per ticket     |
| grounded single task        | `flow-dev` (bug+repro / clear scope / PRD) | —            |
| approved stacked series     | `flow-merge`                             | —              |
| config/deploy/build/audit   | matching domain skill                    | never `flow-dev` |
| multi-session planning      | `wayfinder`                              | —              |
| domain terms / module seams | `domain-modeling` / `codebase-design`    | —              |

Rules:

- Triage ONLY issues you didn't create — `to-tickets` output is agent-ready.
- `flow` drives `brainstorming` / `tdd` / `code-review` internally — never
  invoke them directly, even when their descriptions say "MUST use".
- Converge + decompose in one ~120k window; `handoff` near the limit, `compact`
  at phase breaks. (Bulk work fans out to subagents — see Delegation.)
- No matching route → orchestrate: surgical 1–2 file inline, delegate the rest.

# Decision surfacing (converge vs AFK)

1. **Converge** (direction undecided) → always ask, 2-4 numbered options.
2. **AFK** (plan agreed, executing) → act, report after. "Plan agreed"
   requires affirmative consent ("go ahead", "proceed", explicit pick of a
   numbered option) — passive acknowledgment of a proposal ("that works",
   "sounds fine") does not by itself start AFK.

**Exception:** merge or push → numbered options even mid-AFK (see Safety).

# Safety

**Never push directly to main** — all changes go through PRs.

**Release exception:** `semver-release` may push directly to main, but ONLY
commits limited to `debian/changelog`, `releases/`, and version tags (`v*`).
Any release that also needs code changes: those land via PR first, then
`semver-release` tags the merged result.

**Never merge PRs without explicit user consent** — surface as numbered
options per Decision surfacing above, even when already in an AFK stage.

# Language

Reply to the user in **Traditional Chinese (繁體中文)**, never Simplified.
Keep technical terms, code symbols, command names, file paths, and library
names in English (don't translate `git rebase`, `SessionManager`, …).
Files, code, commits, PRs: write in English.

@RTK.md
@memory-discipline.md
@sandbox-protected-paths.md
@shell-tools.md
@constitution/model-dispatch.md
