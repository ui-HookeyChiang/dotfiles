# Wayfinder Map: codebase-memory-mcp adoption decision

Status: open
Labels: wayfinder:map

## Destination

An adopt/reject decision document for codebase-memory-mcp: whether to install it, on which repos, and how it coexists with the mattpocock skill set (skill prose + context.md/adr/spec docs layer). Both the quantified gap (vs grep / LSP / ast-grep) and the adoption-behavior question (will agents actually use it instead of grep) must be answered before the decision closes.

## Notes

- Tracker: local markdown under `docs/ticket/`; child tickets are sibling files named `2026-08-06-cmm-*.md`; blocking via `Blocked-by:` body lines (no native blocking).
- Test grounds (user-selected): dotfiles, debbox/debfactory, cpss-app/kernel-class large repo. Company repos gated behind security review.
- Integration scope (user-selected): skill prose (flow/flow-dev/research etc.) and docs layer (context.md/adr/spec). Explicitly NOT native-exploration hook routing and NOT subagent tier rebinding (see Out of scope).
- Tool claims to verify: 99.2% token reduction (3.4k vs 412k tokens for 5 structural queries), 158-language tree-sitter + Hybrid LSP for 12 languages, SQLite graph at `~/.cache/codebase-memory-mcp/`, single static binary, 15 MCP tools.
- Skills to consult per session: `/grilling`, `/research`, `/adversarial-review` for the final decision.

## Decisions so far

<!-- one line per closed ticket -->

## Not yet specified

- Skill-prose rewrite details (which sections of flow/flow-dev/research change, and to what) — hangs on the adopt direction and on measured query ergonomics.
- Docs-layer integration (context.md / ADR / spec): the tool has an ADR-ingestion feature; whether/how it maps onto our `docs/adr/` convention is unclear until the tool is exercised.
- Team graph-snapshot workflow (`.codebase-memory/graph.db.zst` committed to repo) — only relevant if adopted on shared repos.
- Benchmark methodology details for the large-repo ground (query set, token accounting) — sharpen after the dotfiles pilot establishes the harness.

## Out of scope

- native-exploration hook routing changes (redirect bare-grep denial toward MCP graph queries) — user scoped integration to skill prose + docs layer; revisit as a fresh effort only if adopted.
- model-dispatch scan-search tier rebinding (Haiku on graph queries) — same reason.
