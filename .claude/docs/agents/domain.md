# Domain docs layout

**Multi-context** repo: root `CONTEXT-MAP.md` indexes the contexts. Vocabulary
and ADRs are layered — system-wide at the root (`CONTEXT.md` + `docs/adr/`) and
context-scoped within each registered context (its own `CONTEXT.md` +
`docs/adr/`). Contexts are grouped by function, not per-skill-directory.

Consumer rules (for `improve-codebase-architecture`, `diagnose`, `tdd`,
`grill-with-docs`):

- Read `CONTEXT-MAP.md` first to find which context(s) the topic touches.
- Read the root `CONTEXT.md` for cross-skill canonical vocabulary, AND the
  relevant context's `CONTEXT.md` for area-scoped terms. Treat `_Avoid_` lists
  as binding (use the canonical term, not the synonym).
- Read `docs/adr/NNNN-*.md` for past decisions — the root `docs/adr/` for
  repo-wide decisions AND the context's `docs/adr/` for context-scoped ones. Do
  NOT re-litigate a recorded decision; surface a conflict only when friction
  genuinely warrants reopening.
- `CONTEXT.md` is a glossary ONLY — no implementation details, no spec content.
- Offer a new ADR only when all three hold: hard to reverse, surprising without
  context, the result of a real trade-off (sequential `NNNN-slug.md` numbering).
  Place it in the context's `docs/adr/` if context-scoped, else the root.

No context has its own `CONTEXT.md`/`docs/adr/` scaffolded yet — until one is
registered in `CONTEXT-MAP.md`, all vocabulary lives in root `CONTEXT.md` and
all ADRs in root `docs/adr/` (the system-wide layer behaves exactly as the
former single-context layout).
