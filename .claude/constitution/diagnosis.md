# Harness Diagnosis — 2026-07-06

Written once, referenced by the other constitution files. Do not re-diagnose from
scratch each session — update this file only when you find NEW evidence, and cite it
(commit hash, file:line, or a specific incident) the way the findings below do.

## Finding 1: Stale names in always-loaded files cause silent misroute

**Evidence:** `~/.claude/CLAUDE.md:5` (global, loads every session, every project) says
"invoke `stacking-dev`". That skill was renamed to `stack-dev` in commit `02edc58f`
(#957). `stacking-dev` now only exists as a historical snapshot under
`docs/dogfoods/stacking-dev/` — invoking it as a live skill fails or, worse, invokes
the wrong artifact if a stale copy happens to resolve. Same file, line 20, pins
delegation to `claude-sonnet-4-6` — the fleet has since moved on (this session runs
`claude-sonnet-5`; Opus 4.8 / Haiku 4.5 also exist). Neither drift was caught because
nothing reads that file back against the live skill list or model catalog.

**Cost:** every session pays to load a routing rule that may point at a dead name.
The failure is silent — the model either can't resolve the skill and guesses, or
finds a decoy (a dogfood/archive copy) and runs stale logic without knowing it.

**Fix:** treat any hardcoded skill-name or model-id string in an always-loaded file
(`CLAUDE.md` at any level) as a liability, not a convenience. Two options, pick
per-case:
1. **Prefer describing the routing rule, not the destination.** "For code changes,
   route through the flagship dev-orchestration skill" survives a rename;
   "`stacking-dev`" does not. Lose a little precision, gain rename-immunity.
2. **If you must hardcode a name** (routing tables need exactness to work), the
   maintenance protocol (deliverable F) requires a stale-reference sweep before any
   edit to that file: `fdfind -t d '^<name>$' .` for every skill name mentioned, `rg`
   for every literal model-id string, confirm each resolves. Never trust that a name
   used to be right.

## Finding 2: Delegation happens, but model/effort tier is never pinned

**Evidence:** `stack-dev/SKILL.md` dispatches multiple agents (`subagent_type: Explore`
at line 62, Dev agent at line 159, red-replay + code-review fan-in at line 177) — none
of these calls pin a `model` or `effort` parameter. The global CLAUDE.md's one model
reference (`claude-sonnet-4-6`, line 20) is both stale (Finding 1) and the *only*
model-tier rule in the entire routing surface — there is no rule anywhere for when a
harder judgment call should run on a stronger model, or when reasoning effort should
step up. Every dispatch defaults to whatever the harness's implicit default is, for
every task regardless of difficulty.

**Cost:** trivial lookups and hard architectural judgment calls get routed at the same
tier. Either the default is too strong (wasted tokens/latency on grep-shaped work) or
too weak (a genuinely hard call — "should we merge these two skills," "is this
refactor safe" — gets a shallow pass because nothing flagged it as needing more).

**Fix:** deliverable C (`model-dispatch.md`) makes model+effort an explicit, required
field of every delegation, with a concrete escalation rubric (deliverable D) driving
the choice — not a vague "use judgment."

## Finding 3: Independent verification is a local pattern, not a portable rule

**Evidence:** `stack-dev/SKILL.md:28,112,177-179` already does this right *inside its
own flow* — Dev agent implements, then **red-replay** and **code-review** run as
separate fan-in checks that don't share the Dev agent's context, so the verifier
can't rubber-stamp its own work. But this discipline is scoped to stack-dev's Phase 2
only. Nothing states it as a standing rule the main session (or any subagent) applies
outside that flow. Concretely: earlier this same session, a project-scope judgment
call (whether to retire a duplicated skill) was resolved by the main agent's own
research and reasoning, with no second opinion and no fresh-context check — not
because that was flagged as acceptable, but because no rule said otherwise.

**Cost:** judgment calls made outside a flow that happens to have baked-in
verification get zero verification. The quality of the outcome depends on which
flow you happened to be in, not on the stakes of the decision.

**Fix:** deliverable C states "verify != self-verify" as a standing, flow-independent
rule: any conclusion that will be acted on (not just code, also judgment calls,
document rewrites, "is this dependency real") gets checked by a fresh-context agent
or a second independent pass before being treated as settled — scaled to stakes per
deliverable D's escalation rubric, not applied uniformly at max cost.

## How to use this file

- Deliverables B–G each cite one or more of these findings instead of re-deriving them.
- If you find a fourth leak with equally concrete evidence, append it here (don't
  create a second diagnosis file — single source of truth, per pruning discipline in
  `skill-guidelines`).
- If a finding above turns out to be wrong or fixed, mark it `RESOLVED <date>` with
  one line of evidence, don't delete it — the history of what leaked is itself useful
  to the next model tuning this system.
