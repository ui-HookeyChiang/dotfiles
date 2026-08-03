#!/usr/bin/env bash
# Offline tests for validate-bindings.sh.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VALIDATOR="$SCRIPT_DIR/../validate-bindings.sh"
SKILL_DIR="$SCRIPT_DIR/../.."
REPO_ROOT="$(cd "$SKILL_DIR/.." && pwd)"
NATIVE="$REPO_ROOT/model-dispatch/native.tsv"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

run_bad() {
  local name="$1" file="$2" expect="$3"
  if bash "$VALIDATOR" --bindings "$file" --inventory "$SKILL_DIR/inventory.tsv" 2> "$TMP/err"; then
    fail "$name unexpectedly passed"
  elif grep -q "$expect" "$TMP/err"; then
    pass "$name"
  else
    fail "$name wrong error: $(tr '\n' ' ' < "$TMP/err")"
  fi
}

run_bad_native() {
  local name="$1" file="$2" expect="$3"
  if bash "$VALIDATOR" --bindings "$SKILL_DIR/bindings.tsv" --inventory "$SKILL_DIR/inventory.tsv" \
      --native "$file" 2> "$TMP/err"; then
    fail "$name unexpectedly passed"
  elif grep -q "$expect" "$TMP/err"; then
    pass "$name"
  else
    fail "$name wrong error: $(tr '\n' ' ' < "$TMP/err")"
  fi
}

if bash "$VALIDATOR" --bindings "$SKILL_DIR/bindings.tsv" --inventory "$SKILL_DIR/inventory.tsv"; then
  pass "current bindings pass"
else
  fail "current bindings pass"
fi

cp "$SKILL_DIR/bindings.tsv" "$TMP/missing.tsv"
python3 - "$TMP/missing.tsv" <<'PYINNER1'
from pathlib import Path
import sys
p=Path(sys.argv[1])
p.write_text('\n'.join(line for line in p.read_text().splitlines() if not line.startswith('decide\t')) + '\n')
PYINNER1
run_bad "missing tier" "$TMP/missing.tsv" "missing tier row: decide"

cp "$SKILL_DIR/bindings.tsv" "$TMP/unknown-model.tsv"
python3 - "$TMP/unknown-model.tsv" <<'PYINNER2'
from pathlib import Path
import sys
p=Path(sys.argv[1])
p.write_text(p.read_text().replace('cursor,composer-2.5,none', 'cursor,no-such-model,none', 1))
PYINNER2
run_bad "unknown model" "$TMP/unknown-model.tsv" "unknown model"

cat > "$TMP/unsupported.tsv" <<'EOF_INNER'
scan	unsupported
scan-search	claude,claude-sonnet-5,low
execute	claude,claude-haiku-4-5,low
execute-review	claude,claude-sonnet-5,low
execute-deep	claude,claude-sonnet-5,low
decide	claude,claude-opus-4-6,low
EOF_INNER
run_bad "blank unsupported" "$TMP/unsupported.tsv" "unsupported row missing action"

cp "$SKILL_DIR/bindings.tsv" "$TMP/missing-tail.tsv"
python3 - "$TMP/missing-tail.tsv" <<'PYINNER3'
from pathlib import Path
import sys
p=Path(sys.argv[1])
p.write_text(p.read_text().replace(';claude,claude-haiku-4-5,low', '', 1))
PYINNER3
run_bad "missing tail" "$TMP/missing-tail.tsv" "missing Anthropic API tail"

if bash "$VALIDATOR" --bindings "$SKILL_DIR/bindings.tsv" --inventory "$SKILL_DIR/inventory.tsv" \
    --native "$NATIVE"; then
  pass "current native.tsv passes"
else
  fail "current native.tsv passes"
fi

cp "$NATIVE" "$TMP/native-diverged.tsv"
python3 - "$TMP/native-diverged.tsv" <<'PYINNER4'
from pathlib import Path
import sys
p=Path(sys.argv[1])
p.write_text(p.read_text().replace('scan\tclaude-haiku-4-5\tlow', 'scan\tclaude-sonnet-5\tlow', 1))
PYINNER4
run_bad_native "native diverges from API tail" "$TMP/native-diverged.tsv" "native.tsv mismatch"

cp "$NATIVE" "$TMP/native-missing-tier.tsv"
python3 - "$TMP/native-missing-tier.tsv" <<'PYINNER5'
from pathlib import Path
import sys
p=Path(sys.argv[1])
p.write_text('\n'.join(l for l in p.read_text().splitlines() if not l.startswith('decide\t')) + '\n')
PYINNER5
run_bad_native "native missing tier" "$TMP/native-missing-tier.tsv" "native.tsv missing tier row: decide"

cp "$NATIVE" "$TMP/native-bad-effort.tsv"
python3 - "$TMP/native-bad-effort.tsv" <<'PYINNER6'
from pathlib import Path
import sys
p=Path(sys.argv[1])
p.write_text(p.read_text().replace('scan\tclaude-haiku-4-5\tlow', 'scan\tclaude-haiku-4-5\tminimal', 1))
PYINNER6
run_bad_native "native bad effort" "$TMP/native-bad-effort.tsv" "invalid effort"

cp "$NATIVE" "$TMP/native-dangling.tsv"
python3 - "$TMP/native-dangling.tsv" <<'PYINNER7'
from pathlib import Path
import sys
p=Path(sys.argv[1])
p.write_text(p.read_text().replace('\tdecide\n', '\tno-such-tier\n', 1))
PYINNER7
run_bad_native "native dangling escalates_to" "$TMP/native-dangling.tsv" "unknown escalates_to"

cp "$NATIVE" "$TMP/native-duplicate.tsv"
python3 - "$TMP/native-duplicate.tsv" <<'PYINNER8'
from pathlib import Path
import sys
p=Path(sys.argv[1])
p.write_text(p.read_text() + 'decide\tclaude-opus-4-6\tlow\tfable\n')
PYINNER8
run_bad_native "native duplicate tier" "$TMP/native-duplicate.tsv" "duplicate tier"

cp "$NATIVE" "$TMP/native-trailing-tab.tsv"
python3 - "$TMP/native-trailing-tab.tsv" <<'PYINNER9'
from pathlib import Path
import sys
p=Path(sys.argv[1])
p.write_text(p.read_text().replace('scan\tclaude-haiku-4-5\tlow\t-\n',
                                   'scan\tclaude-haiku-4-5\tlow\t-\t\n', 1))
PYINNER9
run_bad_native "native trailing tab" "$TMP/native-trailing-tab.tsv" "too many columns"

# --- Topology: cycle detection ---
cp "$NATIVE" "$TMP/native-cycle.tsv"
python3 - "$TMP/native-cycle.tsv" <<'PYINNER10'
from pathlib import Path
import sys
p=Path(sys.argv[1])
# Create cycle: fable→decide (decide→fable already exists)
p.write_text(p.read_text().replace('fable\tclaude-fable-5\tlow\tuser',
                                   'fable\tclaude-fable-5\tlow\tdecide'))
PYINNER10
run_bad_native "native cycle detection" "$TMP/native-cycle.tsv" "cycle detected"

# --- Topology: off-ladder edge ---
cp "$NATIVE" "$TMP/native-off-ladder.tsv"
python3 - "$TMP/native-off-ladder.tsv" <<'PYINNER11'
from pathlib import Path
import sys
p=Path(sys.argv[1])
# scan escalates to decide — not in canonical ladder
p.write_text(p.read_text().replace('scan\tclaude-haiku-4-5\tlow\t-',
                                   'scan\tclaude-haiku-4-5\tlow\tdecide'))
PYINNER11
run_bad_native "native off-ladder edge" "$TMP/native-off-ladder.tsv" "off-ladder escalation"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
