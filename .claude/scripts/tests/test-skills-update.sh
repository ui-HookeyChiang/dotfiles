#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
UPDATE_SCRIPT="$REPO_ROOT/scripts/skills-update.sh"
LOCK_SCRIPT="$REPO_ROOT/scripts/skills-lock.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

hex_a="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
hex_b="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
hex_c="cccccccccccccccccccccccccccccccccccccccc"
hex_d="dddddddddddddddddddddddddddddddddddddddd"

make_sources() {
  local root="$1" alpha_text="$2"
  mkdir -p "$root/matt/skills/engineering/alpha" "$root/darwin"
  printf '# Alpha\n%s\n' "$alpha_text" >"$root/matt/skills/engineering/alpha/SKILL.md"
  printf '# Darwin\n' >"$root/darwin/SKILL.md"
}

write_lock() {
  local lock_file="$1" source_root="$2" matt_ref="$3" darwin_ref="$4" rtk_ref="$5"
  local alpha_hash darwin_hash
  alpha_hash="$(bash "$LOCK_SCRIPT" hash-tree "$source_root/matt/skills/engineering/alpha")"
  darwin_hash="$(bash "$LOCK_SCRIPT" hash-tree "$source_root/darwin")"

  jq -n \
    --arg mattRef "$matt_ref" \
    --arg darwinRef "$darwin_ref" \
    --arg rtkRef "$rtk_ref" \
    --arg alphaHash "$alpha_hash" \
    --arg darwinHash "$darwin_hash" \
    '{
      schemaVersion: 2,
      skillsCli: {package: "skills", version: "9.8.7"},
      sources: {
        "mattpocock/skills": {ref: "HEAD", sourceRef: $mattRef, skills: ["alpha"]},
        "alchaincyf/darwin-skill": {ref: "HEAD", sourceRef: $darwinRef, skills: ["darwin-skill"]},
        "rtk-ai/rtk": {ref: "v1.0.0", tag: "v1.0.0", sourceRef: $rtkRef}
      },
      skills: {
        alpha: {source: "mattpocock/skills", skillPath: "skills/engineering/alpha", treeHash: $alphaHash},
        "darwin-skill": {source: "alchaincyf/darwin-skill", skillPath: ".", treeHash: $darwinHash}
      }
    }' >"$lock_file"
}

run_update() {
  local lock_file="$1" source_root="$2" ticket_dir="$3" audit_cmd="$4"
  SKILLS_UPDATE_LOCK_FILE="$lock_file" \
  SKILLS_UPDATE_TICKET_DIR="$ticket_dir" \
  SKILLS_UPDATE_MATTPOCOCK_SOURCE_DIR="$source_root/matt" \
  SKILLS_UPDATE_DARWIN_SOURCE_DIR="$source_root/darwin" \
  SKILLS_UPDATE_MATTPOCOCK_SOURCE_REF="$hex_a" \
  SKILLS_UPDATE_DARWIN_SOURCE_REF="$hex_b" \
  SKILLS_UPDATE_RTK_TAG="v1.0.0" \
  SKILLS_UPDATE_RTK_SOURCE_REF="$hex_c" \
  SKILLS_UPDATE_AUDIT_CMD="$audit_cmd" \
  SKILLS_UPDATE_INSTALL_CMD="echo install-ran" \
  SKILLS_UPDATE_VERIFY_CMD="echo verify-ran" \
  SKILLS_UPDATE_COMMIT_PR=0 \
  bash "$UPDATE_SCRIPT"
}

same_root="$tmpdir/same"
make_sources "$same_root" "same"
same_lock="$tmpdir/same-lock.json"
write_lock "$same_lock" "$same_root" "$hex_a" "$hex_b" "$hex_c"
same_before="$(sha256sum "$same_lock" | awk '{print $1}')"
same_out="$(run_update "$same_lock" "$same_root" "$tmpdir/tickets-noop" /bin/false)"
same_after="$(sha256sum "$same_lock" | awk '{print $1}')"

[[ "$same_before" == "$same_after" ]] || { echo "FAIL: no-op mutated lock" >&2; exit 1; }
[[ "$same_out" == *"upstream unchanged"* ]] || { echo "FAIL: no-op output missing unchanged message" >&2; echo "$same_out" >&2; exit 1; }

old_root="$tmpdir/old"
new_root="$tmpdir/new"
make_sources "$old_root" "old"
make_sources "$new_root" "new"
fail_lock="$tmpdir/fail-lock.json"
write_lock "$fail_lock" "$old_root" "$hex_d" "$hex_b" "$hex_c"
fail_before="$(sha256sum "$fail_lock" | awk '{print $1}')"
fail_audit="$tmpdir/fail-audit.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$fail_audit"
chmod +x "$fail_audit"

if run_update "$fail_lock" "$new_root" "$tmpdir/tickets-fail" "$fail_audit" >/tmp/skills-update-fail.out 2>/tmp/skills-update-fail.err; then
  echo "FAIL: gate failure returned success" >&2
  exit 1
fi
fail_after="$(sha256sum "$fail_lock" | awk '{print $1}')"
[[ "$fail_before" == "$fail_after" ]] || { echo "FAIL: gate failure mutated lock" >&2; exit 1; }
compgen -G "$tmpdir/tickets-fail/*.md" >/dev/null || { echo "FAIL: gate failure did not write ticket" >&2; exit 1; }

help_out="$(bash "$UPDATE_SCRIPT" --help)" || { echo "FAIL: --help exited non-zero" >&2; exit 1; }
grep -q "^Usage:" <<<"$help_out" || { echo "FAIL: --help did not print usage" >&2; exit 1; }
if bash "$UPDATE_SCRIPT" --bogus >/dev/null 2>&1; then
  echo "FAIL: unknown argument did not error" >&2
  exit 1
fi

echo "[test-skills-update] PASS"
