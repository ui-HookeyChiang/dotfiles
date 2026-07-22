# Issue tracker

Issues and PRDs for this repo live as **local markdown** under `docs/`, colocated
with ADRs:

- **specs** → `docs/spec/`
- **issues** → `docs/ticket/`
- **ADRs** → `docs/adr/` (see [domain.md](domain.md))

Skills that read/write issues (`to-tickets`, `triage`, `to-spec`, `qa`) operate on
files, NOT the `gh` CLI.

## Layout

    docs/
    ├── spec/
    │   └── YYYY-MM-DD-<slug>.md     ← to-spec output
    ├── ticket/
    │   └── YYYY-MM-DD-<slug>.md     ← to-tickets vertical slices
    └── adr/
        └── NNNN-<slug>.md           ← grill-with-docs (sequential, see domain.md)

## Naming

- **spec / ticket** files: `YYYY-MM-DD-<slug>.md` — date-prefixed, aligned with the
  the whole front (spec → ticket) sorts and reads consistently.
- **ADR** files keep `NNNN-<slug>.md` sequential numbering — `grill-with-docs`
  scans for the highest number and increments, and ADRs cross-reference as
  "ADR-0007", so date-prefixing them would break that. ADRs are the one exception.
- Flat dirs, not per-feature subdirectories. The date prefix + slug carries the
  grouping; relate a spec and its issues by a shared slug stem.

## Conventions

- Triage state = a `Status:` line near the top of each file (role strings in
  triage-labels.md). New issues default to `Status: needs-triage`.
- Comments / conversation history append under a `## Comments` heading at the
  bottom of the file.

## Skill verb mapping

- **"publish to the issue tracker"** → create a new file under `docs/spec/`
  (spec) or `docs/ticket/` (issue), named `YYYY-MM-DD-<slug>.md` (mkdir the dir if
  needed). New issues get `Status: ready-for-agent` unless instructed otherwise.
- **"fetch the relevant ticket"** → read the file at the referenced path. The
  user normally passes the path or `<slug>` directly.
- **transition / label change** → edit the `Status:` line in place.
- **completion** → set `Status: done` (Pocock has no native done state; GitHub's
  issue-closed is replaced by this line here).

## Reference: prior backends

This repo's `origin` is `github.com:ubiquiti/prompt-hub`. Issues were previously
tracked in GitHub Issues, then briefly under `.scratch/<feature-slug>/`; both are
retired in favor of the `docs/{spec,ticket}/` layout above. The
`docs/spec/archive/` corpus is unaffected.

## Migration note (Pocock ecosystem adoption, 2026-06)

This repo migrated spec management from the `docs-lifecycle` skill to the Pocock
engineering ecosystem. Spec *files* historically lived under
`docs/spec/{proposed,active,done}/`:

- **`docs/spec/archive/` is NOT migrated to issues.** The full 164-spec done/
  corpus was audited and **archived to `docs/spec/archive/`** (`done/` is now
  empty). Durable value was extracted to `docs/spec/` and the `CONTEXT.md`
  glossary; per-skill rationale stays in each skill's SKILL.md and in the
  archived source spec. `docs/spec/archive/` is read-only history.
- **Active/proposed specs** flow through Pocock (`to-spec` → spec, `to-tickets` →
  tracer-bullet issues, `triage` → routing), now landing as `docs/{spec,ticket}/`
  markdown. See the sample migrations under `docs/agents/samples/` for the
  conversion shape.
- ADRs extracted from specs live in `docs/adr/` (see [domain.md](domain.md)).
