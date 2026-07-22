---
name: stale-drift-canary
description: Canary fixture for the kind=stale drift sub-detector. Red cases must fire; green cases must not.
---

# Stale-drift canary

## Red case A — assertion with zero live referent (MUST FIRE)

The `scripts/validate.py` script enforces the schema on every run. It is the
gate that rejects malformed input before the pipeline starts.

## Red case B — negation contradicted by a live referent (MUST FIRE)

Base-branch protection is human-curated; no auto-gate blocks merges to main.

## Green case — assertion with a live referent (MUST NOT FIRE)

The `enforce_base_branch()` function in `scripts/real_gate.py` blocks merges to
the protected branch.

## Green case — external mechanism, no local referent by design (MUST NOT FIRE)

Merges land via `gh pr merge --squash`; the CI eval gate must be green first.
