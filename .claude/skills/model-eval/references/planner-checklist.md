# Planner scoring — 8-item checklist

Score each plan 1 point per item; pass = >=6/8. Score strictly and
identically across models; grade from the plan text alone.

1. Surfaces the hidden cross-cutting dependency unprompted (for the shipped
   context: the Codex-parity leg; for a new context: pick ONE fact the prompt
   implies but does not state, and check the plan found it).
2. No allowed_files overlap between tasks that can run in PARALLEL (overlap
   along a dependency chain is fine — stacked).
3. Dependency order correct (lib before caller; migrate before delete).
4. Every acceptance_test is a machine-runnable command (prose descriptions,
   `|| true`-vacuous tests, and "review the diff" fail this item).
5. must_preserve names the load-bearing existing behavior (for the shipped
   context: PHASE 6 stale-symlink cleanup).
6. Rollback feasible per task.
7. No scope creep (tasks stay inside the stated objective).
8. Task count 3-6.

Also record (not scored): false-done (claimed artifacts that don't exist),
owner-questions asked (a GOOD signal the checklist can't reward), and any
hidden-ambiguity catches — at n=3 these qualitative notes often decide more
than one checklist point.
