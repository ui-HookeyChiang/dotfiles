#!/usr/bin/env bash
# SC1 — baseline: 5/5 PASS on unchanged prose-guidelines produces APPROVE.
# Pure-orchestration test (does not spawn real LLM voters; verifies the
# ballot-collection + aggregation + render pipeline).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT

RUN_DIR="$TMP/verify-skill-run"; mkdir -p "$RUN_DIR"
for i in 1 2 3 4 5; do mkdir -p "$RUN_DIR/private-A$i"; done
cat > "$RUN_DIR/private-A1/ballot.json" <<'EOF'
{"voter":"A1-trigger","verdict":"TRIGGER_PASS","confidence":"high","evidence":["16/16 cases matched"],"concerns":[],"notes":""}
EOF
cat > "$RUN_DIR/private-A2/ballot.json" <<'EOF'
{"voter":"A2-behavior","verdict":"BEHAVIOR_PASS","confidence":"high","evidence":["3/3 test prompts produced contract-compliant YAML"],"concerns":[],"notes":""}
EOF
cat > "$RUN_DIR/private-A3/ballot.json" <<'EOF'
{"voter":"A3-equivalence","verdict":"NOT_APPLICABLE","confidence":"high","evidence":["effect mode — no before-version"],"concerns":[],"notes":""}
EOF
cat > "$RUN_DIR/private-A4/ballot.json" <<'EOF'
{"voter":"A4-contract","verdict":"CONTRACT_HELD","confidence":"high","evidence":["frontmatter complete","all references exist","scripts referenced exist","Makefile unchanged vs trust root","no corpus rename"],"concerns":[],"notes":""}
EOF
cat > "$RUN_DIR/private-A5/ballot.json" <<'EOF'
{"voter":"A5-adversarial","verdict":"ROBUST","confidence":"high","evidence":["10/10 adversarial cases passed"],"concerns":[],"notes":""}
EOF

python3 "$HERE/voting-harness.py" aggregate "$RUN_DIR" > "$RUN_DIR/verdict.json"
outcome="$(python3 -c "import json,sys; print(json.load(open('$RUN_DIR/verdict.json'))['outcome'])")"
test "$outcome" = "APPROVE" || { echo "FAIL: outcome=$outcome (expected APPROVE)"; exit 1; }
bash "$HERE/render-verdict.sh" "$RUN_DIR" | grep -q 'APPROVE' || { echo "FAIL: render did not include APPROVE"; exit 1; }
echo "PASS: e2e-baseline-approve (SC1)"
