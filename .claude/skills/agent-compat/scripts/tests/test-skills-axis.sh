#!/usr/bin/env bash
# Verify the global skills axis: name GAP with ln -s suggestion, broken-symlink
# DRIFT, divergent-target DRIFT, and clean parity.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPAT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FAKE_HOME="$TMP_ROOT/home"
FAKE_BIN="$TMP_ROOT/bin"
CANON="$FAKE_HOME/.agents/skills"
mkdir -p "$FAKE_HOME/.claude/skills" "$FAKE_HOME/.config/opencode/skills" \
  "$CANON/alpha" "$CANON/beta" "$CANON/gamma" "$CANON/delta" "$TMP_ROOT/elsewhere/gamma" "$FAKE_BIN"

printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_BIN/claude"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_BIN/opencode"
chmod +x "$FAKE_BIN/claude" "$FAKE_BIN/opencode"

# claude sees all four skills
for s in alpha beta gamma delta; do
  ln -s "$CANON/$s" "$FAKE_HOME/.claude/skills/$s"
done
# opencode: alpha OK, beta missing (GAP), gamma points elsewhere (DRIFT),
# delta is a broken symlink (DRIFT)
ln -s "$CANON/alpha" "$FAKE_HOME/.config/opencode/skills/alpha"
ln -s "$TMP_ROOT/elsewhere/gamma" "$FAKE_HOME/.config/opencode/skills/gamma"
ln -s "$TMP_ROOT/nonexistent" "$FAKE_HOME/.config/opencode/skills/delta"

run_check() {
  HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" \
    "$COMPAT_ROOT/scripts/check-compat.sh" --agent opencode --axis skills 2>&1 || true
}

OUTPUT="$(run_check)"

echo "$OUTPUT" | rg -q 'alpha +both' || { echo "FAIL: alpha should be both"; echo "$OUTPUT"; exit 1; }
echo "$OUTPUT" | rg -q 'GAP: +beta +claude only' || { echo "FAIL: beta should be a claude-only GAP"; echo "$OUTPUT"; exit 1; }
echo "$OUTPUT" | rg -q "fix: ln -s .*/.agents/skills/beta .*/.config/opencode/skills/beta" || { echo "FAIL: beta GAP missing ln -s suggestion"; echo "$OUTPUT"; exit 1; }
echo "$OUTPUT" | rg -q 'DRIFTED: +gamma +\(target differs' || { echo "FAIL: gamma should be target-differs DRIFT"; echo "$OUTPUT"; exit 1; }
echo "$OUTPUT" | rg -q 'DRIFTED: +delta +\(broken symlink\)' || { echo "FAIL: delta should be broken-symlink DRIFT"; echo "$OUTPUT"; exit 1; }
echo "$OUTPUT" | rg -q 'summary: 1 gap\(s\), 2 warning\(s\)' || { echo "FAIL: unexpected summary"; echo "$OUTPUT"; exit 1; }

# Clean parity after applying the printed fixes
ln -s "$CANON/beta" "$FAKE_HOME/.config/opencode/skills/beta"
ln -sfn "$CANON/gamma" "$FAKE_HOME/.config/opencode/skills/gamma"
ln -sfn "$CANON/delta" "$FAKE_HOME/.config/opencode/skills/delta"
OUTPUT="$(run_check)"
echo "$OUTPUT" | rg -q 'summary: 0 gap\(s\), 0 warning\(s\), 0 accepted exception\(s\)' || { echo "FAIL: fixes did not converge to clean parity"; echo "$OUTPUT"; exit 1; }

# Reference-side broken symlink: claude's own entry is broken while opencode's
# resolves fine — must blame the reference copy, never emit a blank-source fix,
# and never mislabel the other agent's valid link as target-drift.
rm "$FAKE_HOME/.claude/skills/alpha"
ln -s "$TMP_ROOT/nonexistent-ref" "$FAKE_HOME/.claude/skills/alpha"
OUTPUT="$(run_check)"
echo "$OUTPUT" | rg -q 'DRIFTED: +alpha +\(claude reference entry is a broken symlink' || { echo "FAIL: claude-side broken ref not blamed"; echo "$OUTPUT"; exit 1; }
echo "$OUTPUT" | rg -q 'fix: ln -sfn? +/' && { :; } # fixes may exist for other items
if echo "$OUTPUT" | rg -q 'fix: ln -sfn?  '; then
  echo "FAIL: blank-source fix emitted"; echo "$OUTPUT"; exit 1
fi

echo "PASS: skills axis detects GAP/DRIFT and converges after printed fixes"
