# Codex exploration policy

Codex has no native Read, Grep, or Glob tools — text exploration uses only shell commands. Use these bounded patterns:

## Text reading

**Prefer rg (ripgrep) for content search and bounded reads:**
- `rg --files <pattern>` — list matching files only
- `rg -A 5 -B 5 'pattern' <path>` — search with context
- `rg -n 'pattern' <path>` — line-numbered matches for reference

**sed for bounded line ranges:**
- `sed -n '10,20p' file.txt` — read specific lines only
- Never use bare `sed -n` without bounds (always `N,Np` form)

**Avoid:**
- Whole-file `cat` on large files (>1MB)
- Recursive `grep -r` with broad patterns — use `rg` instead
- Unbounded `find` across the repo root — use `rg --files` for file discovery

## Git inspection

Use git directly for structural inspection (git log, git show, git diff) — these are bounded by design.

## Summary

Guard file reads with size/line bounds. Use deterministic tools (rg, git) before running exploratory loops. Avoid full file reads when rg + sed bounded reads will answer the question.
