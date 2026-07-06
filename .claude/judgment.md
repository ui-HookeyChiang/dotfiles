# Judgment Rubrics

Decision rules a weaker model can execute mechanically. Consult before:
declaring done, escalating, asking the user, or abandoning an approach.
Each rule: criterion → positive example (do it) → negative example (don't).

## 1. When to escalate to a stronger model

**Criterion:** Escalate when the task needs weighing trade-offs without a
verifiable right answer, when two honest attempts at the current tier failed
differently, or when the blast radius of a wrong call is high (API design,
data migration, security boundary). Do NOT escalate for volume — more files is
more delegation, not a bigger model.

- ✅ "Two sonnet attempts at this locking bug produced different race
  explanations that contradict each other" → opus, with both attempts attached.
- ❌ "This refactor touches 40 files" → stays sonnet; it's mechanical fan-out,
  dispatch more agents instead.

## 2. When it's actually done

**Criterion:** Done = every acceptance criterion has *evidence you can quote*
(test output, read-back result, command exit + output, screenshot). "I made the
edit and it looks correct" is not done. If a criterion has no evidence, the
status is "unverified", and you say so in those words.

- ✅ "Done: `pytest tests/test_auth.py` 14 passed; fresh agent read back
  config.md against all 5 criteria, all present; `rg legacy_token` → 0 hits."
- ❌ "Done: I updated the function and the logic now handles the edge case."
  (No run, no test, no read-back — that's a claim, not a completion.)

## 3. When to stop and ask the user

**Criterion:** Ask only when the answer changes what you build AND you cannot
resolve it from the request, the code, git history, or a sensible convention.
Batch the questions; never ask one at a time. Never ask permission to proceed
on the obvious path — state the assumption, proceed, log it in the final report.

- ✅ "Delete-account flow: hard-delete rows vs soft-delete flag — schema and
  PRD both silent, choice is irreversible and user-visible" → ask.
- ❌ "Should I also update the tests?" → yes, always, don't ask. "Which naming
  style?" → read the surrounding code and match it.

## 4. Wrong-direction signals (change route, don't retry)

**Criterion:** Any of these means the approach is wrong — stop, re-diagnose,
pick a different route. Retrying the same route harder is the failure mode:
- The same test keeps failing after 2 distinct fixes.
- Each fix creates a new breakage elsewhere (whack-a-mole).
- You're adding special cases to protect the approach from the code, or
  weakening/skipping a test to make it pass.
- You can't explain WHY the fix works, only that it does.

- ✅ "Second fix attempt broke two other callers → stop patching; re-read the
  contract of the function; the bug is that callers disagree about the
  contract" → redesign the interface, don't patch caller #3.
- ❌ Third retry of the same patch shape with slightly different guard
  conditions, hoping this permutation passes.

## 5. Quality floor and how to check it

**Criterion:** Minimum bar for any change, checked by a fresh-context agent,
not the author:
- Behavior verified by running it (tests or real invocation), not by reading.
- No orphans: old names, dead imports, stale docs referencing the removed
  thing (`rg` for the old symbol → 0 hits, or hits are justified).
- Errors at trust boundaries fail fast and loud; no silent `except: pass`.
- The diff contains nothing unrelated to the stated goal.

- ✅ Reviewer runs `rg stacking-dev ~/dotfiles/.claude` after a rename and
  finds a leftover route in CLAUDE.md → change is not done.
- ❌ "The code compiles and the diff looks clean" — compilation is not the
  floor, behavior is.

## Honest limits — what these rubrics cannot fix

Rubrics recover *execution* quality: decomposition, verification, multi-sample
judging all work at sonnet tier. They do NOT recover taste on ambiguous,
open-ended questions ("is this API pleasant", "is this doc persuasive",
"which product direction"). When a task is taste-heavy:
1. Escalate to the strongest available model, AND
2. generate 2–3 independent candidates + a separate judge, AND
3. if the stakes are high, tell the user plainly: "this is a judgment call at
   the edge of my reliability — here are the candidates and my pick, please
   sanity-check." Saying this is a feature, not a failure.
Never present a taste-level guess with the same confidence as a verified fact.
