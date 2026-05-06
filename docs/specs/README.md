---
title: docs/specs — engineering artifacts index
kind: meta
last_verified: 2026-05-06
summary: Index page for the docs/specs/ directory — proposed/active/done lifecycle subdirs for engineering artifacts
tags: [meta, navigation, specs]
---

# docs/specs/ — engineering artifacts

Engineering specs and implementation plans for this repository. Personal
or knowledge content does not live here; this directory is the engineering
log only.

## Lifecycle subdirs

| dir         | meaning                       | corresponds to                    |
|-------------|-------------------------------|-----------------------------------|
| `proposed/` | drafted, not yet on TODO.md   | (no TODO entry yet)               |
| `active/`   | being executed                | TODO.md `[ ]` items               |
| `done/`     | shipped                       | TODO.md `[x]` + MILESTONES.md     |

A spec lives in exactly one of these dirs at any time. The directory listing
itself functions as a status board, mirroring the `TODO.md [ ]` /
`MILESTONES.md [x]` workflow.

## Naming

`YYYY-MM-DD-<kebab-slug>.md` — the date is the spec's creation date and
never changes (it stays the same as the spec moves between lifecycle dirs).

A `-plan.md` suffix marks an implementation plan paired with a spec of the
same date+slug (e.g. `2026-04-30-foo.md` and `2026-04-30-foo-plan.md`).

## Lifecycle transitions

Transitions are manual and paired — directory placement, TODO.md state, and
frontmatter `status:` must move together.

- **proposed → active**: add a `[ ]` entry to TODO.md referencing
  `docs/specs/active/<slug>.md`, then
  `git mv docs/specs/proposed/<slug>.md docs/specs/active/`.
  Frontmatter `status:` may stay `proposed` until the spec is formally adopted
  into a plan; the lifecycle directory is the operative status marker.
- **active → done**: flip the TODO.md entry to `[x]`, `git mv` the file to
  `docs/specs/done/`, and update the spec's frontmatter `status:` to `done`.
  Add a corresponding entry to MILESTONES.md.

To preserve `git log --follow` history, do pure `git mv` in one commit and
content edits in a follow-up commit.

## Frontmatter contract

Required fields:

- `title`: human-readable title
- `kind`: `spec` (or `plan` for `-plan.md` files)
- `date`: creation date (matches the filename prefix)
- `status`: `proposed` | `active` | `in_progress` | `done`

Optional but encouraged: `related_concepts`, `sources`, `spec` (for plans
that reference a parent spec).

Drift detection between lifecycle dir, frontmatter `status:`, and TODO.md
state is provided by the `Skill docs-lifecycle lint` sub-command.
