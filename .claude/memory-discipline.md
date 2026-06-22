# Recording discipline — where a thing goes before it goes to memory

Auto-memory (`MEMORY.md`) is a pollution source when it stores passive history:
it loads at every session start, has no lifecycle (append-only, never pruned),
and a fresh agent reading stale "killed / shipped / wontfix" verdicts reasons
defensively from them. Most "lessons" do not belong there — they belong in an
active protection that fires at the right moment, or in a tracker that has a
lifecycle. Memory is the last resort, not the default.

## The gate — ask in order before recording anything

1. **Can it be a guardrail?** → write it into a skill / CONTEXT.md / CLAUDE.md.
   A lesson encoded as a guardrail fires automatically; a lesson in memory only
   "hopes I recall it".
2. **Can a mechanism hard-block it?** → a permission `deny`, a hook, or a lint.
   (e.g. broad `git add -A` → settings.json `deny`, not a reminder.)
3. **Is it an architecture decision?** → an ADR.
4. **Is it already done (a shipped PR/feature)?** → git history carries it; record nothing.
5. **Is it a bug, a task, or deferred work?** → create an issue (a single item via
   the triage skill; a large batch via to-prd → to-issues). "Deferred" is a
   schedule, not a new status — the issue existing IS the record; triage schedules it.
6. **Is it an n=1 pitfall observation, not yet guardrail-worthy?** → create an issue,
   `Status: needs-triage`. It is NOT dropped — it is parked where it can accrue
   evidence. When the same class recurs, add it to that issue; once n≥2, triage
   promotes it to a guardrail (back to step 1).
7. **None of the above — a cross-session, non-mechanizable environment fact?**
   (e.g. "this repo's CI marks a skipped required check as BLOCKED", "two checkouts
   share an inode") → THEN memory, one line ≤200 chars, detail in a topic file.

**Only step 7 reaches memory.** Everything else has a better home with a lifecycle.

## Why issues, not memory, for n=1 and deferred

An issue tracker has a state machine (the triage skill drives it: needs-triage →
needs-info / ready-for-agent / ready-for-human / wontfix / done). It gets reviewed,
promoted, or closed — it is pruned. Memory is append-only and loads into every
session's opening context. A pitfall parked as an issue can accumulate a second
occurrence and graduate into a guardrail; the same pitfall in memory just rots and
bloats the context window.

## The skills that move things to their home

- **triage** — create an issue and move it through the role state machine. The
  single entry point for steps 5–6; the only thing that edits an issue's `Status`.
- **to-prd** — when an observation is large enough to be a feature, turn it into a PRD first.
- **to-issues** — break a PRD/plan into independently-grabbable tracer-bullet issues
  (downstream of to-prd; a single observation does not need it).

Promotion chain: `n=1 observation (issue, needs-triage)` → recurs (n≥2) →
`guardrail (step 1)` or, if large, `PRD (to-prd → to-issues)`.

## Project specifics

Paths are per-project. In the skill-dev repo, the issue tracker backend is local
markdown at `docs/issue/YYYY-MM-DD-<slug>.md` (frontmatter `Status:` line), ADRs at
`docs/adr/NNNN-*.md`, and CONTEXT.md / CONTEXT-MAP.md hold the domain model. Other
projects resolve "the issue tracker" / "an ADR" to their own backend; the gate's
*ordering* is what travels, not the paths.
