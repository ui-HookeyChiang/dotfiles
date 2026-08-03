#!/usr/bin/env bash
# Offline tests for check-agent-defs.sh.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKER="$SCRIPT_DIR/../check-agent-defs.sh"
SKILL_DIR="$SCRIPT_DIR/../.."
REPO_ROOT="$(cd "$SKILL_DIR/.." && pwd)"
NATIVE="$REPO_ROOT/model-dispatch/native.tsv"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# fixture_defs <dir> — a tier->def-file tree matching native.tsv.
fixture_defs() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/scan.md" <<'EOF'
---
name: scan
description: "Scan agent."
model: claude-haiku-4-5
effort: low
color: cyan
---
Body.
EOF
  cat > "$dir/scan-search.md" <<'EOF'
---
name: scan-search
description: "Search scan agent."
model: claude-sonnet-5
effort: low
color: cyan
---
Body.
EOF
  cat > "$dir/execute.md" <<'EOF'
---
name: execute
description: "Execute agent."
model: claude-haiku-4-5
effort: low
color: green
---
Body.
EOF
  cat > "$dir/execute-review.md" <<'EOF'
---
name: execute-review
description: "Execute review agent."
model: claude-sonnet-5
effort: low
color: green
---
Body.
EOF
  cat > "$dir/execute-deep.md" <<'EOF'
---
name: execute-deep
description: "Execute deep agent."
model: claude-sonnet-5
effort: low
color: green
---
Body.
EOF
  cat > "$dir/decide.md" <<'EOF'
---
name: decide
description: "Decide agent."
model: claude-opus-4-6
effort: low
color: yellow
---
Body.
EOF
  cat > "$dir/fable.md" <<'EOF'
---
name: fable
description: "Fable agent."
model: claude-fable-5
effort: low
color: yellow
---
Body.
EOF
}

run_ok() {
  local name="$1"; shift
  if bash "$CHECKER" "$@" > "$TMP/out" 2>&1; then
    pass "$name"
  else
    fail "$name: $(tr '\n' ' ' < "$TMP/out")"
  fi
}

run_bad() {
  local name="$1" expect="$2"; shift 2
  if bash "$CHECKER" "$@" > "$TMP/out" 2>&1; then
    fail "$name unexpectedly passed"
  elif grep -q "$expect" "$TMP/out"; then
    pass "$name"
  else
    fail "$name wrong error: $(tr '\n' ' ' < "$TMP/out")"
  fi
}

# --- Real repo state must pass (this is the guard the ticket asks for) ---
run_ok "repo agent defs match native.tsv"

# --- Fixture: aligned tree passes ---
fixture_defs "$TMP/good"
run_ok "aligned fixture passes" --defs-dir "$TMP/good" --native "$NATIVE"

# --- Failure mode 1: model mismatch ---
cp -r "$TMP/good" "$TMP/bad-model"
python3 - "$TMP/bad-model/execute.md" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
p.write_text(p.read_text().replace("model: claude-haiku-4-5", "model: claude-sonnet-4-6"))
PY
run_bad "model mismatch fails" "execute.*model" --defs-dir "$TMP/bad-model" --native "$NATIVE"

# --- Failure mode 2: effort mismatch ---
cp -r "$TMP/good" "$TMP/bad-effort"
python3 - "$TMP/bad-effort/decide.md" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
p.write_text(p.read_text().replace("effort: low", "effort: high"))
PY
run_bad "effort mismatch fails" "decide.*effort" --defs-dir "$TMP/bad-effort" --native "$NATIVE"

# --- Missing effort pin is a mismatch, not a silent pass ---
cp -r "$TMP/good" "$TMP/no-effort"
python3 - "$TMP/no-effort/scan.md" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
p.write_text(p.read_text().replace("effort: low\n", ""))
PY
run_bad "missing effort fails" "scan.*effort" --defs-dir "$TMP/no-effort" --native "$NATIVE"

# --- A mapped tier with no def file is a hard failure (not skipped) ---
cp -r "$TMP/good" "$TMP/absent"
rm "$TMP/absent/decide.md"
run_bad "missing mapped def fails" "decide" --defs-dir "$TMP/absent" --native "$NATIVE"

# --- Mapping is data-driven: a supplied map may check a subset, and adding a
# --- mapping row for a missing def file turns it into a failure. ---
printf 'scan\tscan.md\nexecute\texecute.md\ndecide\tdecide.md\n' > "$TMP/map-ok.tsv"
run_ok "explicit subset map passes" \
  --defs-dir "$TMP/good" --native "$NATIVE" --map "$TMP/map-ok.tsv"

cp -r "$TMP/good" "$TMP/absent-deep"
rm "$TMP/absent-deep/execute-deep.md"
printf 'scan\tscan.md\nexecute\texecute.md\ndecide\tdecide.md\nexecute-deep\texecute-deep.md\n' > "$TMP/map-new.tsv"
run_bad "newly mapped tier without def fails" "execute-deep" \
  --defs-dir "$TMP/absent-deep" --native "$NATIVE" --map "$TMP/map-new.tsv"

# --- A map row naming a tier absent from native.tsv is a config error ---
printf 'scan\tscan.md\nbogus-tier\tbogus.md\n' > "$TMP/map-bogus.tsv"
run_bad "map row for unknown tier fails" "bogus-tier" \
  --defs-dir "$TMP/good" --native "$NATIVE" --map "$TMP/map-bogus.tsv"

# --- YAML-insignificant formatting must not read as drift ---
cp -r "$TMP/good" "$TMP/formatting"
python3 - "$TMP/formatting/scan.md" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
p.write_text(p.read_text()
             .replace("model: claude-haiku-4-5", 'model: "claude-haiku-4-5"   ')
             .replace("effort: low", "effort: low  "))
PY
run_ok "quoted and trailing-space values still match" \
  --defs-dir "$TMP/formatting" --native "$NATIVE"

echo ""
echo "test-check-agent-defs.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
