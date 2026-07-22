#!/usr/bin/env bash
# resolve-skill-creator.sh — resolve the upstream skill-creator skill root ($SC_ROOT).
#
# skill-creator ships as an installed plugin (claude-plugins-official); it has NO
# stable in-repo location. This 4-layer resolver finds its skill root so the
# trigger-eval preparer can invoke run_eval / quick_validate module-style:
#   cd $SC_ROOT && python3 -m scripts.run_eval ...
#
# Resolution order (first valid wins):
#   1. $SKILL_CREATOR_DIR env override — the test-fixture hook (and a manual escape
#      hatch). If set and it validates, use it verbatim.
#   2. installed_plugins.json: jq the key
#      skill-creator@claude-plugins-official [0].installPath, append
#      /skills/skill-creator. The installPath ends in a version dir (e.g. .../unknown)
#      that is STABLE across plugin updates (gitCommitSha is separate metadata) — so
#      we do NOT hardcode any hash.
#   3. fdfind fallback under $HOME/.claude/plugins/cache: locate any
#      skill-creator/*/skills/skill-creator, PREFERRING the hash-free `/unknown/`
#      version dir over any hash dir.
#   4. Validate: test -f $SC_ROOT/scripts/__init__.py (the 0-byte package marker —
#      existence, not non-empty) AND test -f $SC_ROOT/scripts/run_eval.py.
#
# On success: echo $SC_ROOT, exit 0.
# On failure: clear stderr message, exit 2 (not-resolvable).

set -euo pipefail

PLUGINS_JSON="$HOME/.claude/plugins/installed_plugins.json"
PLUGINS_CACHE="$HOME/.claude/plugins/cache"

# validate <dir>: 0 if it is a usable $SC_ROOT (has the two required markers).
validate() {
  local root="$1"
  [[ -n "$root" ]] || return 1
  [[ -f "$root/scripts/__init__.py" ]] || return 1
  [[ -f "$root/scripts/run_eval.py" ]] || return 1
  return 0
}

SC_ROOT=""

# --- Layer 1: env override ---
if [[ -n "${SKILL_CREATOR_DIR:-}" ]]; then
  if validate "$SKILL_CREATOR_DIR"; then
    echo "$SKILL_CREATOR_DIR"
    exit 0
  fi
  echo "resolve-skill-creator: \$SKILL_CREATOR_DIR='$SKILL_CREATOR_DIR' set but missing scripts/__init__.py or scripts/run_eval.py" >&2
  # fall through to the other layers rather than hard-failing on a stale override
fi

# --- Layer 2: installed_plugins.json ---
if [[ -f "$PLUGINS_JSON" ]] && command -v jq >/dev/null 2>&1; then
  INSTALL_PATH="$(jq -r '.plugins["skill-creator@claude-plugins-official"][0].installPath // empty' "$PLUGINS_JSON" 2>/dev/null || true)"
  if [[ -n "$INSTALL_PATH" ]]; then
    CAND="$INSTALL_PATH/skills/skill-creator"
    if validate "$CAND"; then
      echo "$CAND"
      exit 0
    fi
  fi
fi

# --- Layer 3: fdfind fallback (prefer the hash-free /unknown/ version dir) ---
if command -v fdfind >/dev/null 2>&1 && [[ -d "$PLUGINS_CACHE" ]]; then
  # Find skill roots: .../skill-creator/<version>/skills/skill-creator
  MATCHES="$(fdfind --no-ignore -t d -p '/skill-creator/[^/]+/skills/skill-creator$' "$PLUGINS_CACHE" 2>/dev/null || true)"
  if [[ -n "$MATCHES" ]]; then
    # Prefer a /unknown/ path, then fall back to the first that validates.
    PREFERRED="$(printf '%s\n' "$MATCHES" | grep '/unknown/' || true)"
    for CAND in $PREFERRED $MATCHES; do
      if validate "$CAND"; then
        echo "$CAND"
        exit 0
      fi
    done
  fi
fi

# --- Layer 4: nothing resolved ---
echo "resolve-skill-creator: could not resolve skill-creator skill root (\$SC_ROOT)." >&2
echo "  Tried: \$SKILL_CREATOR_DIR override, $PLUGINS_JSON (skill-creator@claude-plugins-official), and fdfind under $PLUGINS_CACHE." >&2
echo "  A valid \$SC_ROOT must contain scripts/__init__.py and scripts/run_eval.py." >&2
exit 2
