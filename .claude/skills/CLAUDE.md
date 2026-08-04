# Skill Repository

## Skill authoring

Never write a SKILL.md without loading `skill-guidelines` first.

## Agent skills

This repo is configured for the mattpocock engineering skills. See `docs/agents/`.

Codex CLI ↔ Claude Code settings mapping: `docs/agents/codex-settings-mapping.md`.

## Hard stops

Structural replan: scope change, new repo/module, public API change,
data-format/schema change, migration reorder, or impossible acceptance criteria
requires asking the human; do not silently raise model effort and continue.

## Issue tracker

Local markdown under `docs/{spec,ticket}/` as `YYYY-MM-DD-<slug>.md` (ADRs in `docs/adr/`, `NNNN-` numbered). See `docs/agents/issue-tracker.md`.

## Triage labels

Five canonical roles via `Status:` line: needs-triage / needs-info / ready-for-agent / ready-for-human / wontfix (+ `done` completion). See `docs/agents/triage-labels.md`.

## Domain docs

Multi-context: root `CONTEXT-MAP.md` indexes contexts; system-wide `CONTEXT.md` + `docs/adr/` at root, context-scoped layers added lazily. See `docs/agents/domain.md`.
