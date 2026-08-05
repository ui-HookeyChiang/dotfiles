# Code-search baselines: Claude Code LSP, ast-grep, grep — vs codebase-memory-mcp

Date: 2026-08-06 · Ticket: docs/ticket/2026-08-06-cmm-research-alternatives.md

Baseline matrix for benchmarking codebase-memory-mcp (tree-sitter + hybrid-LSP knowledge-graph MCP server) against tools agents already have.

## 1. Claude Code built-in LSP tool

- Introduced in Claude Code v2.0.74 as a first-class `LSP` tool.
- Operations (per ClaudeLog / community docs / Serena issue #858): `goToDefinition`, `findReferences`, `hover`, `documentSymbol`, `workspaceSymbol`, `goToImplementation`, `prepareCallHierarchy`, `incomingCalls`, `outgoingCalls`, plus real-time diagnostics.
- Language coverage: via marketplace LSP plugins, ~14+ languages (TypeScript/JavaScript, Python (pyright), Go, Rust (rust-analyzer), Java (jdtls), C/C++ (clangd), C#, PHP, Kotlin, Ruby, Swift, PowerShell, HTML/CSS).
- Setup: two-step per language — install the language-server binary on PATH, then install the `*-lsp` plugin from the official marketplace (`/plugin` Discover tab). Config in `.lsp.json` / `plugin.json`.
- Limits:
  - Per-language server install required; no server → tool silently unavailable (false negatives / crashes, vs grep's benign false positives).
  - Server startup + project indexing latency; misconfigured projects fail hard.
  - Call hierarchy is one-hop-at-a-time (`incomingCalls`/`outgoingCalls`); no persisted whole-repo graph, no cross-session memory, no architecture summary.
  - Observed low trigger rate in practice — agents still reach for grep (see §3).

## 2. ast-grep

- Query model: patterns are *valid parseable code* with meta-variables — `$VAR` (single named node), `$$$` (zero-or-more nodes), repeated `$A` enforces identity, `$_` non-capturing. YAML rules add relational/composite constraints (`kind`, `inside`, `has`, `regex`, `all`/`any`/`not`).
- Strengths: structural (AST-level) match beats regex for syntax-aware search and codemods; Rust + parallel execution — thousands of files in seconds; stateless, zero indexing, tree-sitter grammars so broad language coverage without language servers; good agent fit (CLI, JSON output, MCP server exists).
- Weaknesses: syntax-only — no semantic analysis (types, symbol resolution). Per-file AST scope: no cross-file dependency, inheritance, or call-graph modeling (official docs: patterns "cannot express semantic constraints or cross-file dependencies"). Patterns failing because pattern text isn't syntactically valid is the top usability trap for agents.
- Agent usability: low setup cost, deterministic; but agents must know target-language node kinds to write non-trivial rules.

## 3. Why agents fall back to grep, and what reduces it

Evidence:

- yage.ai analysis "Why Coding Agents Still Use grep": grep wins on zero config (stateless vs LSP init/indexing), universal coverage (YAML/Dockerfile/Markdown too), benign failure mode (false positives LLMs filter easily, vs LSP false negatives/crashes), and shell composability. During *exploration*, grep's noisy concept clusters carry more cognitive value (naming conventions, file distribution) than LSP's precise coordinates — LSP is a precision layer for confirmation/action, not general search. Cites Aider's PageRank-ranked AST repo map and Cursor's n-gram regex index (they accelerated text search rather than abandon it); anecdote: Claude Code LSP "trigger rate is low".
- arXiv 2606.26979 "How Much Static Structure Do Code Agents Need? A Study of Deterministic Anchoring" (2026): pilot on 20 SWE-bench tasks with an optional call-graph tool showed low tool-use — agents defaulted to grep. Graph-based LocAgent trailed a grep-first agent by 23.7 pp on SWE-bench Lite (59.5% vs 83.2%) under matched conditions. Interventions ranked: clearer tool descriptions → marginal; explicit prompting → moderate; hook-based auto-triggering → improved; *forced/programmatic tool use* → largest effect. Agents show path-of-least-resistance behavior; adoption must be architected, not assumed.

Implication for codebase-memory-mcp: the risk is not capability but *adoption*. Value must show on queries grep structurally cannot answer (call paths, dead code, architecture), and delivery likely needs hooks/prompt routing, not just an MCP tool listing.

## 4. Capability matrix

| Query class | grep/ripgrep | ast-grep | Claude Code LSP | codebase-memory-mcp (target) |
|---|---|---|---|---|
| find-definition | Partial — text match, false positives, no symbol resolution | Partial — structural match of declaration shape, per-file, no resolution across imports | **Yes** — `goToDefinition`, exact | Yes (graph node) |
| callers-of / call-path | No — name matches only, no direction | No — no cross-file call graph | Partial — `incomingCalls`/`outgoingCalls` one hop per call; multi-hop path = agent loops N calls | Yes — persisted graph, multi-hop path query |
| cross-file type/import traversal | No — manual chaining | No — per-file AST | Partial — `goToDefinition`/`goToImplementation` hop-by-hop, needs server per language | Yes — edges materialized |
| dead-code detection | No | No (single-file lint rules only) | Partial — `findReferences` per symbol; whole-repo sweep impractical (N symbols × 1 call) | Yes — zero-in-degree query over graph |
| architecture overview | No | No | Partial — `documentSymbol`/`workspaceSymbol` list symbols, no relationships | Yes — module/dependency summary from graph |
| config/text/docs search | **Yes** | No | No | No (out of scope; grep stays) |
| Setup cost | none | none (single binary) | per-language server + plugin | one MCP server + index build |
| Failure mode | false positives (benign) | pattern parse errors | false negatives / server crash | index staleness |

Bottom line: LSP is the strongest existing baseline for find-definition/references; nothing existing answers whole-repo call-path, dead-code, or architecture queries in bounded calls — that is the differentiation surface. Benchmarks must also measure *unprompted adoption*, since forced-use vs free-choice gaps dominate published results.

## Sources

- ClaudeLog — What is LSP Tool in Claude Code: https://claudelog.com/faqs/what-is-lsp-tool-in-claude-code/
- Serena issue #858 (built-in LSP ops, v2.0.74): https://github.com/oraios/serena/issues/858
- Claude Code plugins reference: https://code.claude.com/docs/en/plugins-reference
- CircleCI — Why use LSP with Claude Code: https://circleci.com/blog/claude-code-lsp/
- ast-grep pattern syntax (official): https://astgrep.com/guide/pattern-syntax.html
- ast-grep rule essentials (official): https://ast-grep.github.io/guide/rule-config.html
- ast-grep repo: https://github.com/ast-grep/ast-grep
- yage.ai — Why Coding Agents Still Use grep (2026-03): https://yage.ai/share/why-coding-agents-still-use-grep-en-20260327.html
- arXiv 2606.26979 — How Much Static Structure Do Code Agents Need?: https://arxiv.org/pdf/2606.26979
- antaoalmada.dev — From Grep to Graph: https://antaoalmada.dev/posts/From-Grep-to-Graph/
