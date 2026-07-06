# Model Dispatch

Rules for the main context ("commander") when spawning subagents.
Templates with these rules pre-filled: `.claude/delegation-templates.md`.

## Commander stays out of the trenches

Delegate, don't do, when the task involves any of:
- reading more than 2 files or ~400 lines total to answer one question
- repo-wide search whose result you can't predict in 1–2 Grep calls
- web research (multiple fetches/searches)
- edits touching 3+ files, or mechanical edits across many sites
- reading logs, test output, or build output longer than one screen

The commander itself only: makes decisions, talks to the user, does surgical
1–2 file edits it can specify precisely, and dispatches/verifies everything else.
Only conclusions enter the main context — never raw file dumps.

## The dispatch triple

Every Agent prompt MUST contain all three. Missing one → rewrite before sending:
1. **Goal + why** — what to produce and what decision it feeds, so the agent
   can resolve small ambiguities in the right direction itself.
2. **Acceptance criteria** — falsifiable checks ("all call sites updated, `rg
   old_name` returns 0 hits in src/", not "make sure it's complete").
3. **Report format** — what comes back (see contract below).

## Model + effort selection

Always pass `model` explicitly, aliases only (`haiku`/`sonnet`/`opus`) — never
dated IDs like `claude-sonnet-4-6`; pinned IDs go stale.

| Task shape | Agent type / model | Effort |
|---|---|---|
| Locate/read/inventory ("where is X", "list usages") | `Explore` or `caveman:cavecrew-investigator`, haiku | low |
| Implement/refactor with clear spec | `general-purpose`, sonnet | medium |
| Review, verify, read-back | fresh `general-purpose` or `caveman:cavecrew-reviewer`, sonnet | medium |
| Design with trade-offs, ambiguous spec, 2× failed | `general-purpose`, opus (or best available) | high |

## Report contract (goes verbatim into every dispatch prompt)

> Report back: conclusions only, each with `file:line` references. Any artifact
> longer than ~30 lines (diffs, logs, drafts, tables) goes to a file; return the
> path, not the content. State explicitly what you did NOT check or could not
> verify. No raw file dumps, no narration of your process.

## Escalation / de-escalation

- Sonnet fails the same acceptance criteria **twice with two different
  approaches** → escalate to opus, attaching both failed attempts and why each
  failed. Retrying a third time at the same tier is waste.
- Opus also fails → stop, present both attempts + the blocker to the user.
  Consult `.claude/judgment.md` §3 before asking.
- After an escalated agent produces the design/unblock, mechanical follow-up
  work drops back to sonnet/haiku.

## Verify, never self-verify

The context that produced work never signs it off. After any nontrivial output:
- **Files written** → fresh-context agent reads them back against the
  acceptance criteria (not "does it look good" — check each criterion).
- **Code** → tests, or actually run/exercise the change (`verify` skill);
  typecheck alone is not verification.
- **High-risk or taste-heavy judgment** → second opinion from an independent
  agent, or generate 2–3 candidates and have a separate judge pick.
- Verifier disagrees with producer → the commander reads the specific disputed
  evidence itself and decides; don't loop producer↔verifier more than once.
