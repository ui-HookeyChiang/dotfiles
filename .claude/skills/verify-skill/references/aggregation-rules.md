# Aggregation rules (companion to aggregation-rules.json)

## Vote counting

```
voting_total = 5 - count(NOT_APPLICABLE)
```

## Count-based outcome table

| voting_total | passes | outcome |
|---|---|---|
| 5 | 5 | APPROVE |
| 5 | 4 | APPROVE_WITH_NOTES |
| 5 | 3 | NEEDS_HUMAN |
| 5 | ≤2 | REJECT |
| 4 | 4 | APPROVE |
| 4 | 3 | APPROVE_WITH_NOTES |
| 4 | 2 | NEEDS_HUMAN |
| 4 | ≤1 | REJECT |
| 3 | 3 | APPROVE_WITH_NOTES (degraded — recommend adding adversarial-cases.json) |
| 3 | 2 | NEEDS_HUMAN |
| 3 | ≤1 | REJECT |
| <3 | — | NEEDS_HUMAN (corpus too thin) |

## HC ceilings (post-count override)

- **HC-1**: 5/5 PASS + any voter with `confidence=high` AND non-empty
  `concerns[]` → outcome ceiling = APPROVE_WITH_NOTES.
- **HC-2**: ≥ 2 voters with verdict ∈ {FAIL verdicts} AND
  `confidence=high` → outcome ceiling = NEEDS_HUMAN.

Ceilings only move outcome toward worse (APPROVE → ... → REJECT); never improve.

## Pipeline-mode ceilings (post-HC override)

| pipeline_mode | If outcome would be APPROVE → |
|---|---|
| standalone | unchanged |
| auto-pipeline-create | APPROVE_WITH_NOTES + recommend standalone re-verify |
| auto-pipeline-improve | NEEDS_HUMAN (corpus may have been edited same-run) |
