# codebase-memory-mcp — provenance research

Date: 2026-08-06. Ticket: docs/ticket/2026-08-06-cmm-research-provenance.md.
Scope: facts only; no adopt/security verdict.

## 1. Source availability & license

- Full source present (C, in `src/`, `internal/`, `pkg/`, plus vendored tree-sitter grammars in `vendored/`) — not binary-only. [repo root listing via GitHub API; https://github.com/DeusData/codebase-memory-mcp]
- License: MIT (`license.spdx_id: MIT` from GitHub API; LICENSE in repo root).
- Releases ship pre-built binaries with SHA-256 checksums, Sigstore cosign signatures, SLSA Level 3 provenance, VirusTotal scans per release. [README]

## 2. Author, age, activity

- GitHub account `DeusData` = Martin Vogel, Berlin; personal account (type: User), created 2021-04-01, 452 followers, 22 public repos; bio links LinkedIn (martin-vogel-ab5b66174). [GitHub API `users/DeusData`]
- Co-authors on the research preprint: Falk Meyer-Eschenbach, Severin Kohler, Elias Grünewald, Felix Balzer. [arXiv:2603.27277]
- Repo created 2026-02-24; ~5.5 months old at research date. 37,593 stars, 2,987 forks, 404 open issues/PRs, last push 2026-08-05. [GitHub API `repos/...`]
- 2,069 commits; contributions heavily concentrated: DeusData 1,020 commits, next contributor 53, dependabot 34, long tail of small contributors. [GitHub API `contributors`]
- Release cadence: very frequent — v0.2.1 (2026-02-28) through v0.9.1-rc.1 (2026-07-30); often multiple releases/day early on, roughly monthly minor releases since June. [GitHub API `releases`]
- Issue responsiveness: sample of 10 recently closed issues all closed within hours to ~1 day of filing (e.g. #1449 opened 2026-08-04 19:35, closed 2026-08-05 01:28). [GitHub API `issues?state=closed`]

## 3. Telemetry / network / auto-update claims

- README: "runs 100% locally and collects no telemetry — your code, queries, environment, and usage never leave your machine"; "cbm makes no network request of its own accord — it does not check for new versions in the background, and nothing phones home". [README.md]
- Updates: "run from the install script on every platform, not from inside the running binary" — installer copies `install.sh` next to the binary so the binary can invoke it locally for updates; binary itself never downloads. [README.md; install.sh]
- Source is open, so claims are auditable; this research did not independently audit network code paths. Related open issue: #1134 "installer: make checksum verification fail-closed on missing/malformed checksums.txt" — checksum handling had a fail-open gap as of research date. [issue search]

## 4. One-line installer behavior

`install.sh` (curl | bash):
- Downloads OS/arch-matched binary archive from `https://github.com/DeusData/codebase-memory-mcp/releases/latest/download` (override via `CBM_DOWNLOAD_URL`, HTTPS/localhost only); Linux prefers static "portable" build.
- Verifies SHA-256 against downloaded checksums file before extraction (see fail-closed caveat, issue #1134).
- Installs binary to `~/.local/bin/codebase-memory-mcp` (customizable `--dir`), copies install.sh alongside for later updates, suggests PATH addition; does NOT itself touch agent configs. [install.sh]

Agent-surface configuration is the binary's `install` subcommand ("43 surfaces" = 37 auto-detected + 6 conditional/explicit clients). It modifies per-client MCP config files (`.claude.json`, `.mcp.json`, `.cursor/mcp.json`, `.cline/mcp.json`, `~/.continue/config.yaml`, `~/.copilot/skills`, etc.), writes durable context files (`AGENTS.md`, `SKILL.md`, `CONVENTIONS.md`), and installs hooks (SessionStart, SubagentStart, PreToolUse/PostToolUse, post-Read; PowerShell executor on Windows). Hooks are described as "fail-open and context-only". Three tiered agent profiles (Scout/Verify/Auditor) with per-tier MCP tool allowlists. README's own privacy note: "This tool reads your codebase and writes to your agent configuration files." [README.md]

## 5. The 99.2% token-reduction benchmark

- README wording: "Five structural queries consumed ~3,400 tokens via codebase-memory-mcp versus ~412,000 tokens via file-by-file grep exploration — a 99.2% reduction" (Linux kernel context: 28M LOC indexed in 3 min claim). It is a single 5-query anecdote, not the headline of a controlled study. [README.md]
- `docs/BENCHMARK.md` covers a different thing: language-support evaluation (63 languages, 12 questions each, PASS/PARTIAL/FAIL, Apple M3 Pro, 2026-03-01) — no token-reduction methodology there.
- Peer-reviewable methodology is the preprint arXiv:2603.27277 ("Codebase-Memory: Tree-Sitter-Based Knowledge Graphs for LLM Code Exploration via MCP", Vogel et al.): 31 real-world repos, vs a file-exploration baseline agent — results: 83% answer quality vs 92% for baseline, 10x fewer tokens, 2.1x fewer tool calls; matches/exceeds explorer on 19/31 for graph-native tasks. I.e., the rigorous number is ~10x (90%) token reduction with an answer-quality cost, not 99.2%; 99.2% is the best-case structural-query anecdote.

## Sources

- https://github.com/DeusData/codebase-memory-mcp (README, repo listing)
- GitHub REST API: repos/DeusData/codebase-memory-mcp (+ /contributors, /releases, /issues), users/DeusData (fetched 2026-08-06)
- https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh
- https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/docs/BENCHMARK.md
- https://arxiv.org/abs/2603.27277
- https://deusdata.github.io/codebase-memory-mcp/
