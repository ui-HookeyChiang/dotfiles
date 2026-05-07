---
title: docs/decisions — ADR index
kind: meta
last_verified: 2026-05-06
summary: Index page for the docs/decisions/ directory — flat ADR repository for architectural choices
tags: [meta, navigation, decisions, adr]
---

# docs/decisions/ — Architecture Decision Records (ADRs)

Architecture Decision Records for this repository. These capture significant,
hard-to-reverse architectural choices — not implementation details (those go
in `docs/specs/`).

This is a **flat directory** — there are no `proposed/`, `accepted/`,
`superseded/` subdirs. ADR lifecycle is "until superseded", which is not
symmetric with spec lifecycle ("until done"). Status is expressed via
frontmatter `status:` and the `superseded_by:` / `supersedes:` pair instead.

## Naming

`YYYY-MM-DD-<kebab-slug>.md` — the date is the decision's accepted-on date
and never changes, even if the ADR is later superseded.

## Frontmatter contract

Required fields:

- `title`: human-readable title
- `kind`: `decision`
- `date`: decision-accepted date (matches the filename prefix)
- `status`: one of
  - `proposed` — drafted, not yet accepted
  - `accepted` — currently in force
  - `superseded` — replaced by a newer ADR (must set `superseded_by:`)
  - `deprecated` — no longer in force, but not replaced
  - `rejected` — considered and rejected

### Supersession pattern

When ADR B replaces ADR A:

1. On the **old** ADR (A), set `status: superseded` and add
   `superseded_by: <B-filename>` (sibling filename, no path prefix).
2. On the **new** ADR (B), set `status: accepted` and add
   `supersedes: <A-filename>`.

Both fields use bare sibling filenames (e.g. `2026-04-29-foo.md`), not full
paths, so the references remain valid as the directory moves.
