# Routing-time invisibility, orphans, and portability gaps

Status: needs-triage

## Observations (design calls — need human decision before agent work)

1. **coding-guidelines ↔ code-review pair invisible at routing time** — mutual
   pointers live only in bodies (`coding-guidelines:115`, `code-review:208`);
   code-review's description (`:3`) never mentions guardrails. Descriptions are
   all routing sees. Fix = description edits, but wording is a taste call.
2. **Guideline skills absent from the mandatory routing table** —
   `.claude/CLAUDE.md:7-20` routes nothing to coding-guidelines /
   prose-guidelines / adversarial-review; they're reachable only via downstream
   body loads. Decide: add rows, or accept body-load-only as intended design.
3. **agent-parity orphan** — `disable-model-invocation: true`, zero trigger
   phrases, no sibling references it (`agent-parity/SKILL.md:3,5,61-65`).
   Reached only via SessionStart hook. Intended? If yes, document; if no, wire in.
4. **adversarial-review stale ownership claim** — `:154-156` says spec-gating
   "used by flow-dev"; all 5 call sites are in `flow` (`flow/SKILL.md:50,67,113,
   127,138,243`). Mechanical fix but bundled here since it touches the same file
   as item 1's cluster.
5. **skill-guidelines portability** — hard dependency on `writing-great-skills`
   (`skill-guidelines/SKILL.md:13,15`), which exists only as a
   `~/.claude/skills` symlink installed by `scripts/skills-lock.sh:17`. Bare
   dotfiles clone loses the GLOSSARY. Decide: vendor, degrade gracefully, or
   document as accepted gap in `.agent-parity.json`.

## Origin

skill-guidelines flow-smoothness sweep, 2026-08-04. Severity: rough / design.
