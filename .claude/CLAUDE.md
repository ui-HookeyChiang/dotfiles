# Routing

One rule decides where work goes. Check in order; first match wins:

1. **Code change** (feature, bugfix, refactor, any size incl. one-liners) →
   invoke `stack-dev`. It sizes the work itself — do not pre-judge "too small
   for the flow". Full pipeline from a PRD → `stack`. Merging an approved
   stacked series → `stack-merge`.
2. **Non-code work** (questions, debugging, config, deploys, builds,
   benchmarks, perspective audits) → the matching domain skill, never
   `stack-dev`. For non-code intent/decision clarification, `grill-with-docs`
   is standalone-callable — it is not gated to code work, only `stack`'s own
   scope is.
3. **No matching skill** → orchestrate — do only surgical 1–2 file work
   inline, delegate the rest.

If a routed skill is missing from the loaded list: report what you find to
the user, and do NOT improvise the workflow by hand.

Skills like `brainstorming`, `writing-plans`, `tdd`, … are subordinate — used
inside `stack-dev`'s phases, not invoked directly, even when their
descriptions say "MUST use before any response".

# Delegation

The main context orchestrates and decides; bulk reading, repo scans, web
research, and multi-file edits go to subagents with explicit model + effort,
acceptance criteria, and a report contract. Never accept your own work as
verified — verification goes to a fresh-context agent.

**Report style contract:** ask subagents to write their final report in
caveman style (terse, drop filler prose) — the `SubagentStart` hook already
injects a caveman instruction, but it carves out "required structured
output" from compression, so a report-format request alone won't compress.
Say so explicitly in the prompt. This applies ONLY to the report text back
to the caller — anything the subagent writes to a file (code, commit
messages, PR bodies, spec docs) still follows normal prose / this repo's
`prose-guidelines`, never caveman. State both halves in the prompt so the
subagent doesn't conflate them.

# Decision surfacing (converge vs AFK)

Two modes for whether to ask before acting, checked in order:

1. **Converge stage** (direction not yet settled — multiple viable paths,
   no prior commitment) → always ask, present as 2-4 numbered options.
2. **AFK stage** (direction already settled, executing an agreed plan) →
   act autonomously, report after. Do not re-litigate settled direction.

**Exception — human-permission actions:** merge, push, or any action Safety
below requires explicit consent for, even mid-AFK-stage, still surfaces as
numbered options rather than a silent go-ahead. This is not a new gate —
it's the existing Safety rule expressed in the same options format used at
convergence, so the user gets one consistent interaction shape whether
mid-decision or mid-execution.

Do not layer a separate "was this reversible" test on top — converge/AFK
alone decides; reversibility only matters inside the human-permission
exception above.

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
