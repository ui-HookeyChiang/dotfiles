# Wayfinder Map: codebase-memory-mcp adoption decision

Status: open
Labels: wayfinder:map

## Destination

An adopt/reject decision document for codebase-memory-mcp: whether to install it, on which repos, and how it coexists with the mattpocock skill set (skill prose + context.md/adr/spec docs layer). Both the quantified gap (vs grep / LSP / ast-grep) and the adoption-behavior question (will agents actually use it instead of grep) must be answered before the decision closes.

## Notes

- Tracker: local markdown under `docs/ticket/`; child tickets are sibling files named `2026-08-06-cmm-*.md`; blocking via `Blocked-by:` body lines (no native blocking).
- Test grounds (user-selected, revised 2026-08-08): dotfiles (done) + Linux kernel subsystem (open-source, kernel-class C proxy for cpss/debbox shape). Benchmarking no longer security-gated; security verdict gates company-repo ADOPTION only.
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

- [Linux btrfs large-repo benchmark](2026-08-06-cmm-benchmark-large-repos.md) (skill-dev PR #21) — pilot result INVERTS at kernel scale: cmm (MCP-native, 25-turn cap) scored 8/8 with 2.6-4.2x fewer input tokens and ~3x faster wall at hops>=2; hops-1 and global stay native. Token cut ~60-75% at multi-hop, not 99.2%. Heuristic "one-hop -> native; multi-hop -> cmm" SUPPORTED with a repo-size floor; pilot collapse traced to cli-subprocess tax + 15-turn cap. Index cost: 223k nodes / 8.4s / 2.3GB RAM peak / 279MB disk. Findings: skill-dev docs/research/2026-08-08-cmm-benchmark-linux-btrfs/findings.md

- [Security verdict](2026-08-06-cmm-security-review.md) — PASS-WITH-MITIGATIONS for daily adoption on company repos (user sign-off 2026-08-08). Zero network activity verified empirically; macOS binary is ad-hoc signed (not notarized) so checksum verification is the only integrity gate. Mandatory mitigations: pinned verified release + no `update`; never `install` subcommand (per-project MCP config only, no hooks); cache outside cloud-sync scope + no graph.db.zst in company repos; allowlist cpss-app/debbox/debfactory. Gitignore/secrets-handling verification moved to adopt ticket.

- [grep/lsp/cmm eval — all grounds](skill-dev docs/ticket/2026-08-08-grep-lsp-cmm-eval.md, PR #21) — code-nav-eval skill shipped (verify-skill APPROVE_WITH_NOTES) and run on curl (C+clangd), django (python+pyright), luarocks (lua). Final routing row: hops-1/global -> native everywhere; hops>=2 statically-resolvable languages (C, procedural lua; Go/C# predicted) -> cmm ~2-4x cheaper with equal-or-better correctness; python -> native ALWAYS (cmm graph drops closure/decorator edges, confident false negatives — django q5 answered "no callers" for a twice-called function). Real clangd does not change the verdict. Findings: skill-dev docs/research/2026-08-09-cmm-benchmark-*/

## Not yet specified

- Skill-prose rewrite details (which sections of flow/flow-dev/research change, and to what) — hangs on the adopt direction and on measured query ergonomics.
- Docs-layer integration (context.md / ADR / spec): the tool has an ADR-ingestion feature; whether/how it maps onto our `docs/adr/` convention is unclear until the tool is exercised.
- Team graph-snapshot workflow (`.codebase-memory/graph.db.zst` committed to repo) — only relevant if adopted on shared repos.
- Benchmark methodology details for the large-repo ground (query set, token accounting) — sharpen after the dotfiles pilot establishes the harness.

## Out of scope

- native-exploration hook routing changes (redirect bare-grep denial toward MCP graph queries) — user scoped integration to skill prose + docs layer; revisit as a fresh effort only if adopted.
- model-dispatch scan-search tier rebinding (Haiku on graph queries) — same reason.
