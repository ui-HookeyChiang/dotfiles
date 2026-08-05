# Grilling: security verdict — may the binary touch company repos?

Status: open
Labels: wayfinder:grilling
Parent: 2026-08-06-wayfinder-codebase-memory-mcp-map.md
Blocked-by: 2026-08-06-cmm-research-provenance.md

## Question

Given the provenance research, is it acceptable to run this binary against proprietary code (debbox/debfactory, cpss-app) on a company machine? Decide the gate: pass (proceed to large-repo benchmark), pass-with-mitigations (e.g. sandboxed/network-blocked run, build from source), or fail (dotfiles-only evaluation, tool judged on that ground alone). This is a human trust call — resolve with the user, not AFK.
