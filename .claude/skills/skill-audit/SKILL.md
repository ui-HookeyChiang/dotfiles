---
name: skill-audit
description: Find problems and smells across a skill's whole structure in one report — bloat, duplication, dead code — the read-side holistic counterpart to code-review. Triggers on "audit this skill", "skill smell", "skill health check", "what's wrong with this skill", "find the smells", "找 skill 問題". NOT a single-axis check (invoke the deterministic or probabilistic leg directly), NOT rubric scoring (use darwin-skill), NOT creating or editing a skill (use skill-writer).
argument-hint: <path-to-skill-dir>
landing-group: workflow
---

# skill-audit

Unified read-side audit of a single skill. Runs the deterministic leg via
script, then dispatches the 2 LLM-advisory legs (probabilistic, prose).
Diagnostic-only — never edits, never writes, no `--apply`, no spec generation.

## Run

```bash
python3 ~/.claude/skills/skill-audit/scripts/skill-audit.py <skill-dir>
```

Exit code: `0` = at least one engine found a problem, `2` = all clean, `1` = an engine errored.

## What it runs

| # | Leg | Runner | Tag |
|---|---|---|---|
| 1 | deterministic (deadcode + syntax-metrics + semantic-prefilter) | `skill-audit/scripts/run.sh <skill-dir>` | deterministic (script) |
| 2 | probabilistic (syntax 6-axes + semantic G1/G8) | LLM agent (single, internal file loop) | LLM-advisory (agent) |
| 3 | prose density / meta self-reference | agent: `Skill prose-guidelines <skill>/SKILL.md` (no `--apply`, SKILL.md only, gated > 200 lines) | LLM-advisory (agent) |

Leg 1 runs via the composer script; legs 2-3 are LLM-advisory and dispatched by
the main agent. A full run dispatches exactly **2 agents** regardless of how many
reference files the skill has.

## Deterministic leg (scripts)

Script-only audit. No LLM, no agent dispatch.

```bash
bash ~/.claude/skills/skill-audit/scripts/run.sh <skill-dir>
```

| Sub-leg | Source | Scope |
|---|---|---|
| deadcode reachability | reachability graph | whole skill-dir, one pass |
| syntax metrics | size/imbalance/staleness composite | SKILL.md ∪ references/*.md, `--skill-root` for refs |
| semantic rule-prefilter | G1/G8 candidate detection | SKILL.md (+ G1 over references/*.md) |

Open-concept axes (G1, G8 inline_changelog) emit **candidates labelled "needs
probabilistic confirm"** — the final verdict is owned by the probabilistic leg.

## Probabilistic leg (LLM)

Dispatched as a **single agent** that loops over files internally — never one
agent per file.

1. Build the target set: `SKILL.md ∪ references/*.md`.
2. **Syntax 6-axes** — iterate sequentially over each target internally — for
   each, run
   `bash ~/.claude/skills/skill-audit/scripts/syntax_audit.sh <file>` (advisory
   path, LLM on) and collect findings. For reference files, treat path-links as
   resolving against `<skill-dir>` (skill-root semantics) and suppress
   frontmatter findings on non-SKILL targets.
3. **Semantic G1/G8** — run
   `python3 ~/.claude/skills/skill-audit/scripts/semantic_audit.py <skill-dir>/SKILL.md`
   on SKILL.md only. G8 is SKILL.md-only by nature. G1 is scoped to **this
   skill** — intra-file plus intra-skill near-dup across this skill's own
   `SKILL.md ∪ references/`. Neither G1 nor G8 may use a cross-skill corpus.
4. Fold every syntax + semantic finding into one finding set and emit under
   `## probabilistic`.

## LLM advisory step (mandatory — MUST dispatch both before reporting complete)

The composer script runs leg 1 (deterministic). Before reporting the audit
complete, the main agent MUST dispatch BOTH of the following LLM legs and fold
their findings into the report:

1. **probabilistic** — run the probabilistic leg contract (above) as a single
   agent; fold all findings under a `probabilistic` heading. After dispatching,
   write the trace: `write_audit_leg_trace probabilistic <skill> <log>`.

2. **prose** — run `Skill prose-guidelines <skill>/SKILL.md` (no `--apply`,
   SKILL.md only, gated: SKILL.md > 200 lines); fold findings under a `prose`
   heading. After dispatching, write the trace:
   `write_audit_leg_trace prose <skill> <log>`.

## GATE — hard-stop rule (before reporting complete)

**Before writing the final audit report, MUST assert all 2 LLM legs have a
trace for this skill. If any leg is missing, STOP — dispatch it first, do not
write the final report.**

```bash
source "${HOME}/.claude/skill-dev/_shared/lib/sh/sandwich-trace.sh"
assert_audit_complete <skill-name> "$(cd "$(git rev-parse --git-common-dir)" && pwd)/flow-dev-sandwich.log" || exit 1
```

The gate is objective and log-backed: `assert_audit_complete` checks for
`gate=audit-leg` lines written by `write_audit_leg_trace` after each LLM
dispatch. An absent line means the leg was not dispatched — STOP and dispatch.

## Not this skill

- A numeric rubric score → `darwin-skill`.
- Building or editing a skill → `skill-writer`.
- Prose density only → `prose-guidelines`.
