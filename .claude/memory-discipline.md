# Recording discipline

`MEMORY.md` loads every session and is never pruned, so storing passive history
there pollutes opening context. A lesson belongs in an active protection or a
tracker with a lifecycle — memory is the last resort. Ask in order; stop at the
first match:

1. **Can it be a guardrail?** → skill / CONTEXT.md / CLAUDE.md.
2. **Can a mechanism hard-block it?** → permission `deny`, hook, or lint (e.g. broad `git add -A`).
3. **Architecture decision?** → an ADR.
4. **Already shipped?** → git history carries it; record nothing.
5. **Bug, task, or deferred work?** → an issue (deferred is a schedule, not a status — the issue existing is the record).
6. **n=1 pitfall, not yet guardrail-worthy?** → an issue, `Status: needs-triage`. Parked to accrue evidence; on recurrence (n≥2) triage promotes it to step 1.
7. **A non-mechanizable, cross-session environment fact?** → THEN memory, one line ≤200 chars, detail in a topic file.

Only step 7 reaches memory.

**Movers:** `triage` creates an issue and drives its `Status` state machine (the entry point for steps 5–6). `to-prd` turns a feature-sized observation into a PRD; `to-issues` breaks a PRD/plan into issues (a single observation skips both).

**Per-project:** the gate's *ordering* travels; paths resolve per repo. In skill-dev the tracker is `docs/issue/YYYY-MM-DD-<slug>.md` (frontmatter `Status:`), ADRs are `docs/adr/NNNN-*.md`.
