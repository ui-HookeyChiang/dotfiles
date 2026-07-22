#!/usr/bin/env bash
# auto-detect-mode.sh — emit mode + pipeline_mode + trust_root for verify-skill.
#
# Output (stdout, one key=value per line, parseable):
#   mode=effect|equivalence
#   pipeline_mode=standalone|auto-pipeline-create|auto-pipeline-improve
#   trust_root=<sha or empty>
#   skill_relpath=<repo-relative path>
#
# Exit codes:
#   0 — success
#   2 — preflight error (skill not found, SKILL.md missing)
#   3 — self-invocation
#   4 — bare-clone OR symlinked-skill outside worktree OR outside worktree
#   76 — trust root uncomputable
set -euo pipefail
skill_path="${1:?usage: auto-detect-mode.sh <skill-path>}"

if [[ ! -d "$skill_path" ]]; then
  echo "[STOP] skill path not a directory: $skill_path" >&2; exit 2
fi

# ── Self-invocation guard (SC9) ────────────────────────────────────────
# Compute realpath BEFORE SKILL.md check so self-invocation is detected
# even when verify-skill itself does not yet ship a SKILL.md (task-1b
# precedes task-2 where SKILL.md is added).
skill_real="$(realpath -e "$skill_path")"
verify_skill_real="$(realpath -e "$(dirname "$0")/..")"
if [[ "$skill_real" == "$verify_skill_real" ]]; then
  echo "[STOP] self-invocation: $skill_real == verify-skill installation" >&2
  echo "  remediation: use a separate top-level invocation or independent verifier" >&2
  exit 3
fi

if [[ ! -f "$skill_path/SKILL.md" ]]; then
  echo "[STOP] SKILL.md missing under $skill_path" >&2; exit 2
fi

# ── Symlinked-foreign-repo detection (SC16) ────────────────────────────
# If the caller-visible path is a symlink AND its target lives in a
# different git worktree than the caller's parent dir, refuse. We must
# check this BEFORE cd'ing into the realpath, because after cd we lose
# the caller's worktree context.
caller_parent="$(cd "$(dirname "$skill_path")" && pwd)"
caller_wt="$(git -C "$caller_parent" rev-parse --show-toplevel 2>/dev/null || true)"
target_wt="$(git -C "$skill_real" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -L "$skill_path" && -n "$caller_wt" && -n "$target_wt" && "$caller_wt" != "$target_wt" ]]; then
  echo "[STOP] symlinked skill targets foreign repo: $skill_real" >&2
  echo "  caller_wt=$caller_wt target_wt=$target_wt — corpus-freeze impossible across foreign repo" >&2
  echo "  remediation: grade in standalone mode (separate session) OR --mode effect with explicit ack" >&2
  exit 4
fi

cd "$skill_real"

# ── git presence ───────────────────────────────────────────────────────
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # No git → effect mode, no trust root
  echo "mode=effect"
  echo "pipeline_mode=${VERIFY_SKILL_INVOKED_BY:-standalone}"
  echo "trust_root="
  echo "skill_relpath=$skill_real"
  exit 0
fi

# ── bare-clone refusal (SC12) ──────────────────────────────────────────
if [[ "$(git config --bool core.bare 2>/dev/null || echo false)" == "true" ]]; then
  echo "[STOP] bare clone — verify-skill cannot operate inside bare repo" >&2
  exit 4
fi

# ── Worktree root + skill_relpath (SC16 / R2-v3-H1) ────────────────────
wt_root="$(git rev-parse --show-toplevel)"
# Defense-in-depth: if skill_real is NOT under wt_root, refuse.
case "$skill_real/" in
  "$wt_root/"*) : ;;
  *)
    echo "[STOP] symlinked skill targets foreign repo: $skill_real" >&2
    echo "  wt_root=$wt_root — corpus-freeze impossible across foreign repo" >&2
    echo "  remediation: grade in standalone mode (separate session) OR --mode effect with explicit ack" >&2
    exit 4
    ;;
esac
skill_relpath="${skill_real#$wt_root/}"

# ── Trust root computation (per §Corpus-freeze rule) ───────────────────
TRUNK_REF="${SD_TRUNK_REF:-$(git config flow-dev.trunk-ref 2>/dev/null || echo origin/main)}"
# Opportunistic fetch (offline-safe per R2-v3-H3); failure is logged not fatal.
REMOTE="$(git remote | head -1 || true)"
if [[ -n "$REMOTE" ]]; then
  git fetch --quiet "$REMOTE" "${TRUNK_REF#$REMOTE/}" 2>/dev/null \
    || echo "[WARN] could not fetch $TRUNK_REF — trust root may be stale" >&2
fi
if ! TRUST_ROOT="$(git merge-base "$TRUNK_REF" HEAD 2>/dev/null)" || [[ -z "$TRUST_ROOT" ]]; then
  echo "[STOP] cannot compute trust root from $TRUNK_REF" >&2
  echo "  remediation: 'git config flow-dev.trunk-ref <ref>' or set SD_TRUNK_REF" >&2
  exit 76
fi

# ── Effect vs equivalence (per spec §Auto-detect mode) ─────────────────
# Pathspecs are resolved relative to CWD; we are cd'd into the skill dir
# so use `git -C "$wt_root"` to anchor pathspecs at the worktree root.
# 1. Skill dir untracked / absent from HEAD?
if ! git -C "$wt_root" ls-tree HEAD -- "$skill_relpath" 2>/dev/null | grep -q .; then
  mode="effect"
# 2. Uncommitted diff (working tree OR staged)?
elif ! git -C "$wt_root" diff --quiet HEAD -- "$skill_relpath" \
     || ! git -C "$wt_root" diff --cached --quiet HEAD -- "$skill_relpath"; then
  mode="equivalence"
# 3. --before override (env BEFORE_REF)?
elif [[ -n "${BEFORE_REF:-}" ]]; then
  mode="equivalence"
# 4. Committed refactor: skill existed at trust root AND trust_root..HEAD diff non-empty?
elif git -C "$wt_root" ls-tree "$TRUST_ROOT" -- "$skill_relpath" 2>/dev/null | grep -q . \
     && ! git -C "$wt_root" diff --quiet "$TRUST_ROOT" HEAD -- "$skill_relpath"; then
  mode="equivalence"
else
  mode="effect"
fi

# ── Pipeline mode (SC15) ───────────────────────────────────────────────
INVOKED_BY="${VERIFY_SKILL_INVOKED_BY:-standalone}"
if [[ "$INVOKED_BY" == "skill-writer" ]]; then
  if git -C "$wt_root" ls-tree "$TRUST_ROOT" -- "$skill_relpath" 2>/dev/null | grep -q .; then
    pipeline_mode="auto-pipeline-improve"
  else
    pipeline_mode="auto-pipeline-create"
  fi
else
  pipeline_mode="standalone"
fi

echo "mode=$mode"
echo "pipeline_mode=$pipeline_mode"
echo "trust_root=$TRUST_ROOT"
echo "skill_relpath=$skill_relpath"
exit 0
