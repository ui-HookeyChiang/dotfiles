---
name: example-skill
description: An example skill describing a fully shipped feature — no future/deferred language; naive keyword match might fire on "Phase" but behavior is live.
expected: NEGATIVE — shipped feature description; no unbuilt markers; must NOT flag kind=unbuilt
---

# Example Skill

## Phase breakdown

The audit runs in three phases, all of which are fully implemented:

**Phase 1 — Parse.** The target SKILL.md is read and tokenised. Frontmatter
is extracted via the YAML block between the leading `---` delimiters. The
`scripts/` directory is walked to build a file listing used by later phases.

**Phase 2 — Detect.** Advisory metrics (size, imbalance, staleness, phrase
hints) are computed by `scripts/audit.py`. The LLM advisory pass is dispatched
by the main agent after `audit.sh` returns.

**Phase 3 — Report.** The metric brief and LLM findings are merged and emitted
to stdout. No files are written unless `--write-spec` is passed explicitly.

All three phases execute on every invocation. There is no partial-phase mode.
