# Report format + spec generation

## Report format

```markdown
# skill-syntax-audit report: <skill-name>

**Target**: <path-to-SKILL.md>
**Total lines**: <N>
**Scripts dir**: <path-to-scripts/ or "none">
**Generated spec**: <path-to-docs/spec/proposed/...md>

## Bloat metrics

| Severity | Redundancy findings | Scriptifiable findings | Script-side info |
|---|---|---|---|
| HIGH | N | N | — |
| MED | N | N | — |
| LOW | N | N | N |
| **Estimated lines saved if all applied** | **N** | | |

## Findings

### R1 (HIGH) — verify-then-promote pattern duplicated
- Locations: lines 210-215 (Phase 1 Step 1.3) and 388-403 (Phase 2 Step 4)
- Duplicated content: "invoke `Skill docs-lifecycle promote <slug> <target>` after L1/L2 review"
- Proposed refactor: extract the 3-step verify-promote-verify pattern to `scripts/promote-with-verify.sh <slug> <target>`, replace both sites with `bash scripts/promote-with-verify.sh ...`
- Estimated saved: 18 lines

### S1 (MED) — Phase 2 worktree creation chain
- Location: lines 290-310
- Content: 7 chained bash commands (git fetch, mkdir, prune, branch -D, rm, worktree add fallback)
- Proposed refactor: extract to `scripts/create-task-worktree.sh <task-num> <base-branch>`
- Estimated saved: 18 lines

## Spec generated

A docs-lifecycle proposal spec has been written to:
  `docs/spec/proposed/2026-05-15-<skill>-audit-cleanup.md`

To land the cleanup:
  `Skill flow-dev` and point it at the spec slug `<skill>-audit-cleanup`.
```

## Spec generation

The spec is written in the host repo's docs-lifecycle format. The skill:

1. Resolves the host repo by walking up from the target SKILL.md until it finds `.docs-lifecycle.json` (using docs-lifecycle's own resolver)
2. If no `.docs-lifecycle.json` is found, falls back to printing the spec content to stdout with a note: "no host docs-lifecycle config found — copy the spec body below into your repo's proposed/ dir manually"
3. The spec contains:
   - Frontmatter: `kind: spec`, `status: proposed`
   - Background section linking to the skill-syntax-audit run that generated it
   - Goals section: one goal per finding (HIGH and MED only; LOW becomes optional follow-up)
   - Task contract: each finding maps to one task with concrete acceptance criteria
   - Test plan: lint-stop-prefixes still PASS, docs-lifecycle lint still clean (no regression)

The spec naming convention is `<YYYY-MM-DD>-<skill-name>-audit-cleanup.md` so `Skill flow-dev` picks it up via `Skill docs-lifecycle to-stacking <slug>`.
