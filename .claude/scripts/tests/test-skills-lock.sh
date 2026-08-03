#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_SCRIPT="$SCRIPT_DIR/../skills-lock.sh"

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
export SKILLS_LOCK_SKILLS_CLI_VERSION="9.8.7"

bash "$LOCK_SCRIPT" regen >/dev/null

jq -e '
  .schemaVersion == 2
  and .skillsCli.version == "9.8.7"
  and .sources["mattpocock/skills"].sourceRef == "ed37663cc5fbef691ddfecd080dff42f7e7e350d"
  and .sources["alchaincyf/darwin-skill"].sourceRef == "2fbaf4171e453d5c66fc8109a296ae89c4772bc3"
  and .sources["rtk-ai/rtk"].tag == "v0.44.0"
  and .skills.alpha.skillPath == "skills/engineering/alpha"
  and .skills.beta.skillPath == "."
  and (.skills.alpha.treeHash | test("^sha256:[0-9a-f]{64}$"))
  and (.skills.beta.treeHash | test("^sha256:[0-9a-f]{64}$"))
' "$lock_file" >/dev/null

bash "$LOCK_SCRIPT" verify >/dev/null

printf '\nchanged\n' >>"$skills_root/alpha/references/detail.md"
if bash "$LOCK_SCRIPT" verify >/dev/null 2>&1; then
  echo "FAIL: verify passed after whole-tree content drift" >&2
  exit 1
fi

git_restore_lock="$(cat "$lock_file")"
rm -rf "$skills_root/alpha"
if bash "$LOCK_SCRIPT" regen >/dev/null 2>"$tmpdir/regen.err"; then
  echo "FAIL: regen succeeded with a missing skill directory" >&2
  exit 1
fi
grep -q "refusing to write invalid treeHash for alpha" "$tmpdir/regen.err" || {
  echo "FAIL: regen did not name the skill with the invalid hash" >&2
  exit 1
}
[ "$(cat "$lock_file")" = "$git_restore_lock" ] || {
  echo "FAIL: regen mutated the lock file despite failing" >&2
  exit 1
}

echo "[test-skills-lock] PASS"
