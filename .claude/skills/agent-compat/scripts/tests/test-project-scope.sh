#!/usr/bin/env bash
# Verify --scope project: instructions PASS (symlink and @AGENTS.md forms),
# CLAUDE.md-only GAP, skills bridging GAP + ln -s suggestion, per-repo
# accepted-gap suppression and PAST-REVIEW warning.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPAT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

CHECK="$COMPAT_ROOT/scripts/check-compat.sh"

run_project() {
  AGENT_COMPAT_PROJECT_DIR="$1" "$CHECK" --scope project 2>&1 || true
}

# Case 1: symlink form PASS + bridged skills PASS
P1="$TMP_ROOT/p1"
mkdir -p "$P1/.claude/skills/finance" "$P1/.opencode/skill"
echo "# shared" > "$P1/AGENTS.md"
ln -s AGENTS.md "$P1/CLAUDE.md"
ln -s ../../.claude/skills/finance "$P1/.opencode/skill/finance"
OUT="$(run_project "$P1")"
echo "$OUT" | rg -q 'PASS: CLAUDE.md and AGENTS.md resolve to the same file' || { echo "FAIL: symlink form should PASS"; echo "$OUT"; exit 1; }
echo "$OUT" | rg -q 'finance +both' || { echo "FAIL: bridged skill should be both"; echo "$OUT"; exit 1; }
echo "$OUT" | rg -q 'summary: 0 gap\(s\), 0 warning\(s\)' || { echo "FAIL: p1 should be clean"; echo "$OUT"; exit 1; }

# Case 2: @AGENTS.md import form PASS (Claude-specific remainder allowed)
P2="$TMP_ROOT/p2"
mkdir -p "$P2"
echo "# shared" > "$P2/AGENTS.md"
printf '@AGENTS.md\n\n# Claude-specific\nMCP table here\n' > "$P2/CLAUDE.md"
OUT="$(run_project "$P2")"
echo "$OUT" | rg -q 'PASS: CLAUDE.md imports AGENTS.md' || { echo "FAIL: @AGENTS.md form should PASS"; echo "$OUT"; exit 1; }

# Case 2b: reverse direction — AGENTS.md is a symlink to CLAUDE.md (canonical
# file kept as CLAUDE.md) must also PASS
P2B="$TMP_ROOT/p2b"
mkdir -p "$P2B"
echo "# shared" > "$P2B/CLAUDE.md"
ln -s CLAUDE.md "$P2B/AGENTS.md"
OUT="$(run_project "$P2B")"
echo "$OUT" | rg -q 'PASS: CLAUDE.md and AGENTS.md resolve to the same file' || { echo "FAIL: reverse symlink form should PASS"; echo "$OUT"; exit 1; }

# Case 3: CLAUDE.md-only repo -> instructions GAP with split suggestion;
# unbridged project skill -> GAP with ln -s suggestion
P3="$TMP_ROOT/p3"
mkdir -p "$P3/.claude/skills/finance"
echo "# claude only" > "$P3/CLAUDE.md"
OUT="$(run_project "$P3")"
echo "$OUT" | rg -q 'GAP: +AGENTS.md +missing \(CLAUDE.md-only repo\)' || { echo "FAIL: CLAUDE.md-only should GAP"; echo "$OUT"; exit 1; }
echo "$OUT" | rg -q 'fix: ln -s CLAUDE.md' || { echo "FAIL: missing symlink suggestion"; echo "$OUT"; exit 1; }
echo "$OUT" | rg -q 'GAP: +finance +claude only' || { echo "FAIL: unbridged skill should GAP"; echo "$OUT"; exit 1; }
echo "$OUT" | rg -q "fix: mkdir -p $P3/.opencode/skill && ln -s ../../.claude/skills/finance" || { echo "FAIL: missing ln -s suggestion"; echo "$OUT"; exit 1; }
echo "$OUT" | rg -q 'summary: 2 gap\(s\)' || { echo "FAIL: p3 should have 2 gaps"; echo "$OUT"; exit 1; }

# Case 4: per-repo accepted gap suppresses; past review_by warns
cat > "$P3/.agent-compat.json" <<EOF
{"accepted_gaps": {
  "instructions": [{"item": "AGENTS.md", "reason": "claude-only repo by choice", "review_by": "2099-01-01"}],
  "skills": [{"item": "finance", "reason": "opencode never opens this repo", "review_by": "2000-01-01"}]
}}
EOF
OUT="$(run_project "$P3")"
echo "$OUT" | rg -q 'ACCEPTED: +AGENTS.md' || { echo "FAIL: accepted instructions gap not suppressed"; echo "$OUT"; exit 1; }
echo "$OUT" | rg -q 'PAST-REVIEW: +finance' || { echo "FAIL: past review_by should warn"; echo "$OUT"; exit 1; }
echo "$OUT" | rg -q 'summary: 0 gap\(s\), 1 warning\(s\), 1 accepted exception\(s\)' || { echo "FAIL: unexpected p3 accepted summary"; echo "$OUT"; exit 1; }

# Case 4b: wildcard project accepted gap covers any skill item
mkdir -p "$P3/.claude/skills/second-skill"
cat > "$P3/.agent-compat.json" <<EOF
{"accepted_gaps": {
  "instructions": [{"item": "AGENTS.md", "reason": "claude-only repo by choice", "review_by": "2099-01-01"}],
  "skills": [{"item": "*", "reason": "opencode never opens this repo", "review_by": "2099-01-01"}]
}}
EOF
OUT="$(run_project "$P3")"
echo "$OUT" | rg -q 'ACCEPTED: +finance' || { echo "FAIL: wildcard did not accept finance"; echo "$OUT"; exit 1; }
echo "$OUT" | rg -q 'ACCEPTED: +second-skill' || { echo "FAIL: wildcard did not accept second-skill"; echo "$OUT"; exit 1; }
echo "$OUT" | rg -q 'summary: 0 gap\(s\), 0 warning\(s\), 3 accepted exception\(s\)' || { echo "FAIL: unexpected wildcard summary"; echo "$OUT"; exit 1; }

# Case 4c: broken claude-side project skill symlink must surface as DRIFTED,
# not be silently skipped
P4C="$TMP_ROOT/p4c"
mkdir -p "$P4C/.claude/skills"
ln -s ../../nonexistent-target "$P4C/.claude/skills/ghost"
OUT="$(run_project "$P4C")"
echo "$OUT" | rg -q 'DRIFTED: +ghost +\(claude project entry is a broken symlink' || { echo "FAIL: broken project entry not surfaced"; echo "$OUT"; exit 1; }

# Case 5: no project instructions or skills -> nothing to check, exit 0
P5="$TMP_ROOT/p5"
mkdir -p "$P5"
OUT="$(AGENT_COMPAT_PROJECT_DIR="$P5" "$CHECK" --scope project 2>&1)" || { echo "FAIL: empty project should exit 0"; echo "$OUT"; exit 1; }
echo "$OUT" | rg -q 'no project instructions' || { echo "FAIL: missing nothing-to-check notice"; echo "$OUT"; exit 1; }

# Case 6: global-only axis under project scope prints skip reason, exit 0
OUT="$(AGENT_COMPAT_PROJECT_DIR="$P5" "$CHECK" --scope project --axis hooks 2>&1)" || { echo "FAIL: global-only axis should exit 0"; echo "$OUT"; exit 1; }
echo "$OUT" | rg -q "axis 'hooks' is global-only" || { echo "FAIL: missing skip reason"; echo "$OUT"; exit 1; }

echo "PASS: project scope instructions + skills checks behave per spec"
