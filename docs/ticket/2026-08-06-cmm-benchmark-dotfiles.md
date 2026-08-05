# Task: dotfiles pilot benchmark — token cost and answer quality vs grep/LSP/ast-grep

Status: open
Labels: wayfinder:task
Parent: 2026-08-06-wayfinder-codebase-memory-mcp-map.md
Blocked-by: 2026-08-06-cmm-research-alternatives.md

## Question

Build the benchmark harness and run the pilot on dotfiles: install codebase-memory-mcp locally (personal repo — no security gate), index the repo, and run a fixed query set (find-definition, callers-of, cross-file lookup, dead-code, architecture overview) four ways — MCP graph query, native Grep/Glob, Claude Code LSP, ast-grep. Record tokens consumed, wall time, and answer correctness per query. Output: harness (reusable for the large-repo ground) plus a results table testing the 99.2% claim at small scale. AFK.
