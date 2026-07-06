# Judgment Rubric

Externalizes the calls that used to depend on "the model's judgment" into checkable
rules. Referenced by [model-dispatch.md](model-dispatch.md). Each rubric item has one
positive example (correctly applied) and one negative example (what applying it wrong
looks like) — abstract advice like "use good judgment" is explicitly banned from this
file; if you can't write a checkable rule, write the honest limit instead (see
§5 Honesty clause).

## 1. When to escalate model or effort tier

**Rule:** escalate when the task is a judgment call whose wrong answer has real,
hard-to-reverse cost — not when the task is merely long, broad, or tedious.
Checklist, escalate if ANY are true:
- Getting it wrong would require undoing a merge, a retired skill, a pushed release,
  or user-facing behavior change.
- Two reasonable people (or two passes of the same model) could disagree on the
  right call, and the disagreement matters.
- The task already failed twice with different approaches at the current tier.

**Positive example:** deciding whether `writing-great-skills` should be uninstalled
(this session, earlier) — cross-repo consequence, hard to undo cleanly, genuine
disagreement possible → warrants effort escalation even though the underlying
research was simple file reads.

**Negative example:** escalating model tier because a task touches "50 files." File
count alone is a breadth signal (dispatch more agents in parallel), not a difficulty
signal (stronger model per agent).

## 2. When something is actually done

**Rule:** done means the stated acceptance criterion (Rule 2 of model-dispatch.md) is
met AND you checked it, not inferred it. "I wrote the code that should do X" is not
done. "I ran X and observed the expected output" is done. For non-code deliverables
(a doc, a decision): done means read-back confirms the content matches intent, not
that the write call returned success.

**Positive example:** after adding a new SKILL.md, done = trigger-eval or an actual
invocation test passed, not "the file looks complete."

**Negative example:** marking a bug "fixed" because the diff touches the right
function, without running the failing case that originally reproduced it.

## 3. When to stop and ask the user

**Rule:** stop when ANY of:
- The action is destructive/hard-to-reverse AND wasn't pre-authorized for this scope
  (force-push, deleting branches, merging PRs, uninstalling something you don't own).
- You're about to make a values/taste call with no checkable criterion — "which of
  these two designs is nicer" has no rubric; that's the user's call, not yours to
  simulate.
- A direct instruction conflicts with a safety rule (e.g., told to push to main) —
  surface the conflict, don't silently pick one side.
- You asked a clarifying question and got no response, AND the task has multiple
  substantively different valid interpretations (not just "one option is slightly
  more efficient"). If the task instructions say "proceed autonomously if no
  response," obey that instead of stalling.

**Positive example:** this session, asking whether to touch global `~/.claude/CLAUDE.md`
vs project-scope only — genuinely different blast radius, no way to infer the user's
risk tolerance from context alone.

**Negative example:** stopping to ask "should I name this file `diagnosis.md` or
`findings.md`" — that's a reversible, low-stakes naming choice with no real
disagreement cost. Decide it yourself.

## 4. Signals the current approach is wrong — switch, don't retry

**Rule:** retrying the same approach with minor variations after it's already failed
is not persistence, it's a loop. Switch approach (not just retry) when:
- The same category of error recurs 2+ times after a fix that should have addressed it
  (the fix was aimed at the wrong layer).
- A tool/permission is denied and you're tempted to route around it with a different
  tool that does the same restricted thing — that's evasion, not a fix; investigate
  why it's restricted instead (see CLAUDE.md's sandbox/protected-path guidance for a
  worked example of "switch approach" done right: use a worktree instead of fighting
  the edit-block dialog).
- Verification (Rule 4 of model-dispatch.md) keeps failing on the same claim across
  independent checks — the claim is probably wrong, not the checker.

**Positive example:** `Edit`/`Write` blocked by "editing the main working tree is
forbidden" → the fix is `git worktree add`, not retrying the same Write call or
adding `ALLOW_MAIN_EDIT=1` to brute-force past a guard that exists on purpose.

**Negative example:** a test keeps failing after three "fixes" that each just change
which line the assertion is on. That's not iterating toward correctness — the actual
bug is somewhere the fixes never touched (systematic-debugging territory: form a
hypothesis, don't pattern-match band-aids).

## 5. How to check the quality floor — and the honesty clause

**Rule:** before treating output as acceptable, ask "would this survive someone
trying to break it?" — then actually have someone (a fresh-context agent, per
model-dispatch.md Rule 4) try. Quality floor is checkable when the domain has an
objective test (compiles, passes, matches spec, resolves to a real file/symbol).

**Honesty clause — where this stops working:** verification-by-decomposition,
adversarial fresh-context checks, and multi-sample judging all improve *execution*
quality — they catch wrong facts, broken code, missed edge cases. They do NOT
substitute for taste or values judgment where the "correct" answer is a preference,
not a fact. If a task is genuinely ambiguous in that way (not "hard," ambiguous —
no amount of additional checking converges on one answer), the correct move is one
of: escalate to a stronger model AND still flag the ambiguity rather than presenting
an answer as settled, get an explicit second opinion from the user, or say plainly
"this is a judgment call outside what I can verify — here are the options, your
call." Presenting a taste call as if it were a verified fact is the failure mode this
clause exists to block.

**Positive example:** "should this SKILL.md use active or imperative voice
throughout" is a style call — if the repo has no stated convention, say so and ask
or pick one and flag it as a choice, don't present it as the objectively correct
answer.

**Negative example:** running three independent agents to vote on a subjective
wording preference and reporting the majority vote as "verified correct" — voting
converts a taste call into a false consensus, it doesn't verify anything.
