#!/usr/bin/env bash
# SC2 — regression: widened-scope prose-guidelines gets REJECT with ≥3 high-conf FAIL.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap "rm -rf $TMP" EXIT

RUN_DIR="$TMP/verify-skill-run"; mkdir -p "$RUN_DIR"
for i in 1 2 3 4 5; do mkdir -p "$RUN_DIR/private-A$i"; done
cat > "$RUN_DIR/private-A1/ballot.json" <<'EOF'
{"voter":"A1-trigger","verdict":"TRIGGER_FAIL","confidence":"high","evidence":["7/16: blog query now triggers"],"concerns":["scope widened in description"],"notes":""}
EOF
cat > "$RUN_DIR/private-A2/ballot.json" <<'EOF'
{"voter":"A2-behavior","verdict":"BEHAVIOR_PASS","confidence":"medium","evidence":["spec input still passes"],"concerns":[],"notes":""}
EOF
cat > "$RUN_DIR/private-A3/ballot.json" <<'EOF'
{"voter":"A3-equivalence","verdict":"DIVERGED","confidence":"high","evidence":["blog input was refused before; now compressed"],"concerns":["scope change"],"notes":""}
EOF
cat > "$RUN_DIR/private-A4/ballot.json" <<'EOF'
{"voter":"A4-contract","verdict":"CONTRACT_BROKEN","confidence":"high","evidence":["description widened to include 'blog/essay' but Use-when says SKILL.md only"],"concerns":["contradiction in scope"],"notes":""}
EOF
cat > "$RUN_DIR/private-A5/ballot.json" <<'EOF'
{"voter":"A5-adversarial","verdict":"FRAGILE","confidence":"high","evidence":["adv-blog-essay-style now produces findings; expected refusal"],"concerns":["out-of-scope detection broken"],"notes":""}
EOF

# aggregate exits 1 on REJECT (by spec — see voting-harness main()); that
# is the expected outcome here, so do not let set -e abort.
set +e
python3 "$HERE/voting-harness.py" aggregate "$RUN_DIR" > "$RUN_DIR/verdict.json"
rc=$?
set -e
test "$rc" = "1" || { echo "FAIL: harness exit=$rc (expected 1 for REJECT)"; exit 1; }
outcome="$(python3 -c "import json; print(json.load(open('$RUN_DIR/verdict.json'))['outcome'])")"
test "$outcome" = "REJECT" || { echo "FAIL: outcome=$outcome (expected REJECT)"; exit 1; }
hc_fails="$(python3 -c "
import json
d = json.load(open('$RUN_DIR/verdict.json'))
fail_verdicts = {'TRIGGER_FAIL','BEHAVIOR_FAIL','DIVERGED','CONTRACT_BROKEN','FRAGILE'}
hc = sum(1 for b in d['breakdown'] if b['verdict'] in fail_verdicts and b['confidence']=='high')
print(hc)
")"
test "$hc_fails" -ge 3 || { echo "FAIL: only $hc_fails high-conf FAILs (need ≥3)"; exit 1; }
echo "PASS: e2e-regression-reject (SC2; $hc_fails high-conf FAILs)"
