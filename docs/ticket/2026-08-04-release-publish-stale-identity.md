# release-publish: stale pre-merge copy — frontmatter name and contract contradict all callers

Status: ready-for-agent

## Problem

`.claude/skills/release-publish/SKILL.md` is a stale pre-merge version:

- Frontmatter declares `name: release-announce` (`SKILL.md:2`); body self-identifies
  as `release-announce` throughout (`:9`, `:18-28`, `:43`). Callers chain to
  `release-publish`: `semver-release/SKILL.md:35-36,201,221`, `flow-merge/SKILL.md:171,194`.
- References non-existent upstream skill `release-note` at `:13,:47,:87,:89,:92,:167`,
  claiming "Publishes only — does NOT generate notes. Use `release-note` first."
- `semver-release/SKILL.md:38` states the opposite: `release-publish` folded
  `release-note` + `release-announce` into one call.

The release chain's downstream node is unresolvable by name and its input contract
points at a skill that no longer exists.

## Fix

Rewrite via `skill-writer` (modify mode): set `name: release-publish`, remove all
`release-note` references, align body with the merged note+announce behavior that
`semver-release` describes. Verify chain: flow-merge → semver-release → release-publish.

## Acceptance

- `grep -r 'release-announce\|release-note' .claude/skills/release-publish/` returns nothing.
- Frontmatter name matches directory name.
- `check-parity.sh --scope project` reports 0 gaps.

## Origin

skill-guidelines flow-smoothness sweep, 2026-08-04 (release/infra cluster). Severity: BROKEN.
