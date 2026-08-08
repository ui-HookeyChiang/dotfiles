# Grilling: security verdict — may the binary touch company repos?

Status: done
Labels: wayfinder:grilling
Parent: 2026-08-06-wayfinder-codebase-memory-mcp-map.md
Blocked-by: 2026-08-06-cmm-research-provenance.md

## Question

Given the provenance research, is it acceptable to run this binary against proprietary code (debbox/debfactory, cpss-app) on a company machine? Decide the gate: pass (proceed to large-repo benchmark), pass-with-mitigations (e.g. sandboxed/network-blocked run, build from source), or fail (dotfiles-only evaluation, tool judged on that ground alone). This is a human trust call — resolve with the user, not AFK.

## Verdict (2026-08-08, user sign-off in session)

**PASS-WITH-MITIGATIONS** — covers daily adoption on company repos, not just benchmarking.

Basis: threat model = code exfiltration + compliance (supply-chain exposure accepted as already-incurred, shared with the dotfiles evaluation); verification level 2 (behavioral spot-check) satisfied — zero network activity observed under lsof sampling during index+query, checksum manually verified. New fact: macOS binary is ad-hoc signed (not notarized) — OS trust chain does not apply; our own checksum verification is the only integrity gate. No company policy on third-party local tools reading source (user-confirmed); self-judged criteria: local execution, no egress, open source auditable.

Mitigations (all mandatory):
1. Pinned checksum+cosign-verified release only (currently v0.9.0); `update` subcommand forbidden; upgrades re-run manual verification.
2. Never run `install` subcommand. Registration is per-project scoped MCP config only; no cmm hooks, no cmm-written context files (AGENTS.md/SKILL.md).
3. Cache (`~/.cache/codebase-memory-mcp/`, contains code snippets) must not be inside any personal cloud-sync/backup scope; `--persistence` graph artifacts (graph.db.zst) forbidden in company repos — derived source never committed.
4. Repo allowlist: cpss-app, debbox, debfactory; other company repos case-by-case.

Follow-up (moved to adopt-decision ticket): empirically verify cmm respects .gitignore / does not index secret files.
