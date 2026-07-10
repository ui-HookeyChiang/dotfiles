# Routing

One rule decides where work goes. Check in order; first match wins:

1. **Code change** (feature, bugfix, refactor, any size incl. one-liners) →
   invoke `flow-dev`. It sizes the work itself — do not pre-judge "too small
   for the flow". Full pipeline from a spec → `flow`. Merging an approved
   stacked series → `flow-merge`.
2. **Non-code work** (questions, debugging, config, deploys, builds,
   benchmarks, perspective audits) → the matching domain skill, never
   `flow-dev`. For non-code intent/decision clarification, `grill-with-docs`
   is standalone-callable — it is not gated to code work, only `flow`'s own
   scope is.
   - spec authoring → `to-spec` (replaces to-prd)
   - ticket breakdown → `to-tickets` (replaces to-issues)
   - large multi-session planning → `wayfinder`
3. **No matching skill** → orchestrate — do only surgical 1–2 file work
   inline, delegate the rest.

If a routed skill is missing from the loaded list: report what you find to
the user, and do NOT improvise the workflow by hand.

Skills like `brainstorming`, `writing-plans`, `tdd`, … are subordinate — used
inside `flow-dev`'s phases, not invoked directly, even when their
descriptions say "MUST use before any response".

# Delegation

The main context orchestrates and decides; bulk reading, repo scans, web
research, and multi-file edits go to subagents with explicit model + effort,
acceptance criteria, and a report contract. Never accept your own work as
verified — verification goes to a fresh-context agent.

# Safety

**Never push directly to main** — all changes go through PRs.

**Release exception:** `semver-release` may push directly to main, but ONLY
commits limited to `debian/changelog`, `releases/`, and version tags (`v*`).
Any release that also needs code changes: those land via PR first, then
`semver-release` tags the merged result.

**Never merge PRs without explicit user consent.**

# Language

Reply to the user in **Traditional Chinese (繁體中文)**, never Simplified.
Keep technical terms, code symbols, command names, file paths, and library
names in English (don't translate `git rebase`, `SessionManager`, …).
Files, code, commits, PRs: write in English.
