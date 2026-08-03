#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

skills_root="$tmpdir/skills"
lock_file="$tmpdir/skills-lock.json"
mkdir -p "$skills_root/alpha/references" "$skills_root/beta"

cat >"$skills_root/alpha/SKILL.md" <<'EOF'
# Alpha
EOF
cat >"$skills_root/alpha/references/detail.md" <<'EOF'
reference content
EOF
cat >"$skills_root/beta/SKILL.md" <<'EOF'
# Beta
EOF

export SKILLS_LOCK_FILE="$lock_file"
export SKILLS_LOCK_SKILLS_ROOT="$skills_root"
export SKILLS_LOCK_MATTPOCOCK_SKILLS="alpha"
export SKILLS_LOCK_DARWIN_SKILLS="beta"

cd "$REPO_ROOT"
scripts/skills-lock.sh regen >/dev/null
make -s skills-lock-verify >/dev/null

printf '\nchanged\n' >>"$skills_root/alpha/references/detail.md"
if output="$(make -s skills-lock-verify 2>&1)"; then
  echo "FAIL: make skills-lock-verify passed after subfile drift" >&2
  exit 1
fi

if [[ "$output" != *"DRIFT alpha"* ]]; then
  echo "FAIL: drift output did not name alpha" >&2
  echo "$output" >&2
  exit 1
fi

echo "[test-skills-lock-verify-target] PASS"
