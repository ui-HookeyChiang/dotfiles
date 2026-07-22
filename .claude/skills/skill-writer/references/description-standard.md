# Description Standard

The `description:` frontmatter is what Claude sees to decide whether to load
the skill. This standard is the **writing-skills strict派** position:
description = pure triggering conditions, never workflow summary.

## Rules

1. **Description = triggering conditions ONLY.** Never summarize the
   workflow; never list phases. Empirical case: when description carried a
   workflow summary, Claude treated the summary as "enough" and skipped
   reading the body — the gate inside the body never fired.
2. **Start with `Use when ...`.** Front-load the triggering signal so
   Claude's decision happens on the first clause.
3. **Cover edge-case triggers explicitly.** Name the rationalizations users
   reach for to skip the skill (`rewrite`, `refactor`, "just adding a
   section", "small edit"). If the description doesn't name them, users
   will rationalize past the skill.
4. **Third-person, no "I can help you...".** Description is read by a
   router, not spoken to a user.
5. **≤ 1024 characters.** Frontmatter limit; longer descriptions are
   truncated silently by some readers.

## Examples

BAD (current `skill-writer/SKILL.md` v1 description — workflow summary):

```
Create or modify skills with mandatory dedup sweep. Wraps skill-creator
with overlap detection, refactoring proposals, and integration checks.
Use instead of skill-creator when working in this repo.
```

Why bad: "Wraps skill-creator with overlap detection, refactoring
proposals, and integration checks" is a workflow summary. Claude reads it
and decides it understands what skill-writer does without reading the body.
The mandatory dedup-sweep gate inside the body never fires.

GOOD (Candidate A from the SSOT spec):

```
Use when creating, modifying, refactoring, or rewriting any skill in this
repo. Use even for small SKILL.md edits, single-file skill changes, or
"just adding a section" — never invoke skill-creator directly. Use for
v1→v2 rewrites that need baseline failure measurement.
```

## Anti-patterns

| Pattern | Why bad | What to do instead |
|---|---|---|
| "This skill helps you ..." | second-person, also leaks workflow | "Use when ..." + drop the helper framing |
| Lists phases / steps in description | Claude treats summary as sufficient, skips body | Move to body; description states ONLY triggers |
| "Use for X" with one keyword only | misses edge-case rationalizations | enumerate the rationalizations users reach for |
| Description > 1024 chars | silently truncated by some readers | tighten or move detail to body |

## Override

Rare. Rule 1 (no workflow summary) should never be overridden — empirical
case shows it is universally harmful. If you must override Rule 3 (edge
cases) because the skill genuinely has none, declare
`standard-override: description-rule-3 (no edge-case triggers exist)` in
frontmatter; A5 Adversarial will challenge the claim.

## Validation

A1 Trigger voter reads `evals/trigger-eval.json` and exercises the
description against ≥ 16 cases (≥ 8 positive, ≥ 8 negative). Target: true-
positive ≥ 80% AND false-positive ≤ 20%. A4 Contract checks the ≥ 16-case
threshold and the description length ≤ 1024 chars.
