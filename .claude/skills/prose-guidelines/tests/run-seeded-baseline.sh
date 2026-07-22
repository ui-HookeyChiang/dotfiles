#!/usr/bin/env bash
# run-seeded-baseline.sh — end-to-end test runner for prose-guidelines v2.
#
# Spec File 7 (docs/specs/active/2026-05-29-prose-guidelines-v2-coverage.md):
#   1. Spawn prose-guidelines detection agent on tests/fixtures/seeded-v2-baseline.md.
#   2. For each expected positive paragraph P*, assert a finding exists with
#      matching `finding_class` and (for lexical) `lexical_hits_count` within tolerance.
#   3. For each negative paragraph (P8-P11), assert NO finding cites those lines.
#   4. Compute per-class detected count; compare to expected_count - per_class tolerance.
#
# Limitation
#   The detection agent is invoked via the Claude Code Skill harness — it is
#   NOT directly callable from a shell script. This runner is therefore a
#   STUB that documents the manual invocation contract; the deterministic
#   path lives in tests/fixtures/seeded-v2-agent-output.yaml + validate-findings.sh
#   (run via the test plan in the spec).
#
#   Manual invocation:
#     1. From a Claude Code session, run:
#          /skill prose-guidelines prose-guidelines/tests/fixtures/seeded-v2-baseline.md
#     2. Capture the agent's YAML output to /tmp/seeded-v2-actual.yaml.
#     3. Run:
#          python3 prose-guidelines/tests/run-seeded-baseline.py \
#            --actual /tmp/seeded-v2-actual.yaml \
#            --expected prose-guidelines/tests/fixtures/seeded-v2-expected.yaml \
#            --baseline prose-guidelines/tests/fixtures/seeded-v2-baseline.md
#        (run-seeded-baseline.py is the comparator; not implemented in v2,
#         deferred to Task 3 per docs/specs/active spec's task split.)
#
# Until that comparator lands, this script syntax-checks cleanly (`bash -n`)
# and exits 0 so CI does not block on it.

set -euo pipefail

cat <<'MSG'
run-seeded-baseline.sh — STUB (manual invocation required).

The Claude Code Skill harness cannot be invoked from a shell script directly.
See the header comment in this file for the manual test contract; the
deterministic validator-level test lives in:

  tests/fixtures/seeded-v2-agent-output.yaml + scripts/validate-findings.sh

To run that deterministic test:

  bash prose-guidelines/scripts/validate-findings.sh \
    prose-guidelines/tests/fixtures/seeded-v2-agent-output.yaml \
    prose-guidelines/tests/fixtures/seeded-v2-baseline.md

MSG

exit 0
