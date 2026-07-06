# Maintenance Protocol

How a future model (any tier — this is written to be executable by Sonnet-class
models, not just stronger ones) safely updates this constitution
(`~/dotfiles/.claude/constitution/*.md`, `@`-included from the global
`~/dotfiles/.claude/CLAUDE.md`, which every project session loads via the
`~/.claude/CLAUDE.md` symlink).

## Where lessons get recorded — don't reinvent this

`~/dotfiles/.claude/memory-discipline.md` already defines the recording-discipline
gate (7-step decision tree: guardrail → mechanism → ADR → git/PR → triage → n=1
observation → MEMORY, in that priority order, stop at first match). That gate is
global and applies to lessons learned anywhere, including while working on these
constitution files. Do not create a competing decision tree here. What THIS file
adds is specific to the constitution files themselves: when you may edit them
directly vs must ask first, and how they get pruned.

## Edit freely, no need to ask

- Fixing a confirmed stale reference (dead skill name, dead file path, wrong model
  ID) in any constitution file — this is mechanical correction, not a policy change.
- Appending a new `RESOLVED <date>` note to an existing finding in `diagnosis.md`
  when you have concrete evidence it's fixed.
- Adding a new positive/negative example to an existing rubric item in
  `judgment-rubric.md`, as long as it illustrates the EXISTING rule rather than
  introducing a new one.
- Fixing a broken cross-reference between these files (e.g. a link that points to a
  renamed file).

## Ask the user first

- Adding, removing, or changing a RULE (not an example) in `judgment-rubric.md` or
  `model-dispatch.md` — these are the load-bearing policy surface; a wrong rule
  propagates into every future session that reads it.
- Adding a NEW `@`-include line to `~/dotfiles/.claude/CLAUDE.md` for a topic outside
  this constitution's existing scope — that expands what loads in every session
  everywhere; the user should make that call explicitly, not have it happen as a
  side effect of an unrelated edit.
- Deleting a finding from `diagnosis.md` outright (mark `RESOLVED`, don't delete —
  the history of what leaked is itself useful).
- Restructuring which file a topic lives in (e.g. moving model-tier rules out of
  `model-dispatch.md` into a new file) — ask first; this is exactly the kind of
  reorganization that silently breaks other files' cross-references if done without
  updating every pointer.

## New finding, discovered by using this system

When you find a NEW leak/failure mode (not one of the three already in
`diagnosis.md`) with concrete evidence — append it to `diagnosis.md` following the
existing format (Evidence / Cost / Fix), don't create a second diagnosis file. If the
fix requires a new rule (not just a new example), that's the "ask the user first"
path above, because a new rule change the routing rules downstream files depend on.

## Pruning threshold

These files are reference (good-class 2 per `skill-guidelines`), not steps — they're
meant to accumulate slowly, not churn. Prune when:
- A finding in `diagnosis.md` has been `RESOLVED` for 2+ months with no recurrence —
  compress it to one line ("Finding N, resolved <date>, see commit <hash>") instead
  of keeping the full Evidence/Cost/Fix block.
- Any file exceeds roughly 150 lines — that's the signal to split by branch (per
  `skill-guidelines`'s granularity rule), not to keep appending. Check whether the
  new material is really a distinct branch (different task shape, different
  reader) before splitting; if it's just more of the same rule, tighten the prose
  instead (see `prose-guidelines`).
- Two files start saying the same thing in different words — collapse to one,
  cross-reference from the other. Single source of truth applies to this
  constitution as much as it applies to the skills it governs.

## The CLAUDE.md routing stub

`~/dotfiles/.claude/CLAUDE.md` should only ever contain a short `@constitution/<file>.md`
include line per constitution file — not inlined policy. If you find yourself wanting
to add more than 2-3 lines directly to `CLAUDE.md` for a constitution-related topic,
that content belongs in one of these files instead. This file's own existence is the
reason: don't undo it by re-inlining content back into `CLAUDE.md` over time.
