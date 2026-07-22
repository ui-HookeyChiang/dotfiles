# Spec review checklist (approval gate user pause)

Render this checklist to the user during the approval-gate pause in `flow-dev`
(Phase 1 Step 1.2). The user must explicitly approve (`[y]`) — there is no
countdown and no auto-approve. `[n]` aborts and leaves the spec untouched.

Walk through each item in order. Don't skim — these four questions are
the structural gate that catches most spec defects before they reach
implementation.

1. **Success criteria measurable?** Each criterion in the spec should
   be independently runnable as a shell command or yield a checkable
   artifact. Vague criteria like "improves UX" or "is faster" fail this
   check — push back to brainstorming.

2. **Test plan runnable?** The spec should describe how each success
   criterion will actually be exercised — fixtures, commands, expected
   exit codes. If a criterion has no matching test step, the spec is
   incomplete.

3. **Task contract between sub-tasks clear?** If the spec splits work
   into multiple tasks, each task's input/output (files touched,
   contracts produced/consumed) must be explicit so parallel Dev agents
   don't collide. Single-task specs can skip this item.

4. **Scope creep — anything in spec that doesn't belong?** Look for
   sections that drifted in during brainstorming (nice-to-haves,
   tangential refactors, "while we're here" cleanups). Cut them now
   before they expand task count.

5. **Advisory points addressed?** The spec-advisory always ran (always-3
   rule). Walk back through the findings the advisor surfaced. Each HIGH
   finding should either be incorporated into the spec or consciously
   rejected with a one-line reason. MED/LOW findings are optional but
   should not be silently dropped — the advisor exists to broaden your
   review, not to be ignored.
