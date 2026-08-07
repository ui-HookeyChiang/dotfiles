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
- Routing heuristic under test (folded into dotfiles benchmark): one-hop queries → native tools (grep/ast-grep/LSP); multi-hop / whole-graph → cmm. Multi-hop = step 2's query parameters depend on step 1's results; benchmark query set stratified `hops: 1/2/3/global`, scored per layer. Cross-service HTTP linking is cmm-unique but least-verified.
- Benchmark ticket body moved to skill-dev docs/ticket/ (skill-dev PR #21); pointer file remains here.
- Skills to consult per session: `/grilling`, `/research`, `/adversarial-review` for the final decision.

## Decisions so far

<!-- one line per closed ticket -->

- [Research: codebase-memory-mcp provenance, license, and network behavior](2026-08-06-cmm-research-provenance.md) — MIT open source (C + vendored tree-sitter), signed releases (SLSA L3/cosign); solo-dominant author, repo ~5.5 months old, 37.6k stars; README claims no telemetry/self-update; installer's `install` subcommand touches 43 agent surfaces incl. hooks; 99.2% claim is a single anecdote — controlled study (arXiv:2603.27277) shows ~10x token cut at 83% vs 92% answer quality; installer checksum check currently fail-open (issue #1134). Findings: docs/research/2026-08-06-codebase-memory-mcp-provenance.md
- [Research: baseline landscape — LSP tool, ast-grep, and agent grep behavior](2026-08-06-cmm-research-alternatives.md) — Claude Code LSP covers definition/references/one-hop calls (needs per-language server, low unprompted use); ast-grep is per-file syntax-only (no call graph); grep-first beat a graph agent by 23.7 pp on SWE-bench Lite, and forced use > hooks > prompting > descriptions for driving structured-tool adoption; whole-repo call-path/dead-code/architecture queries are the tool's open differentiation surface. Findings: docs/research/2026-08-06-code-search-baselines.md

- [dotfiles pilot benchmark](2026-08-06-cmm-benchmark-dotfiles.md) (moved to skill-dev PR #21) — 99.2% token claim refuted at small scale: cmm used the MOST input tokens in every hops layer (1.5x native at hops-1, 3-7x at hops>=2) and returned empty answers on both hops-3 cells (turn-cap exhaustion); native arms 7-7.5/8 correctness vs cmm 5.5/8. Heuristic "multi-hop -> cmm" not supported on small repos. Caveats: n=1/cell, cli-subprocess arm not MCP-native, small repo. Findings: skill-dev docs/research/2026-08-08-cmm-benchmark-dotfiles/findings.md

## Not yet specified

- Skill-prose rewrite details (which sections of flow/flow-dev/research change, and to what) — hangs on the adopt direction and on measured query ergonomics.
- Docs-layer integration (context.md / ADR / spec): the tool has an ADR-ingestion feature; whether/how it maps onto our `docs/adr/` convention is unclear until the tool is exercised.
- Team graph-snapshot workflow (`.codebase-memory/graph.db.zst` committed to repo) — only relevant if adopted on shared repos.
- Benchmark methodology details for the large-repo ground (query set, token accounting) — sharpen after the dotfiles pilot establishes the harness.

## Out of scope

- native-exploration hook routing changes (redirect bare-grep denial toward MCP graph queries) — user scoped integration to skill prose + docs layer; revisit as a fresh effort only if adopted.
- model-dispatch scan-search tier rebinding (Haiku on graph queries) — same reason.
