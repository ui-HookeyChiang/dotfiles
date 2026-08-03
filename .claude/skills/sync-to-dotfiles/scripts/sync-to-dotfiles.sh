#!/usr/bin/env bash
# sync-to-dotfiles.sh — one-way sync skill-dev → personal dotfiles.
#
# Copies hooks, generic skills, and docs/agents into the dotfiles repo,
# EXCLUDING ubiquiti-* skills (work-specific, must not enter personal dotfiles).
#
# Idempotent. Dry-run by default; pass --apply to write. Leaves dotfiles
# UNCOMMITTED so you review + commit yourself.
#
# Override paths via env: SRC=<skill-dev checkout> DST=<dotfiles/.claude>.
# SRC should point at a clean tree on origin/main (e.g. a worktree) so you
# don't sync uncommitted local edits.
set -euo pipefail

SRC="${SRC:-$HOME/.claude/skill-dev}"
DST="${DST:-$HOME/dotfiles/.claude}"
APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

say() { printf '%s\n' "$*"; }

[[ -d "$SRC" ]] || { echo "missing SRC: $SRC" >&2; exit 1; }
[[ -d "$DST" ]] || { echo "missing DST: $DST" >&2; exit 1; }

# ── 1. Full hooks/ tree ─────────────────────────────────────────────────────
say "== hooks (full tree) =="
h_count=0
if [[ -d "$SRC/hooks" ]]; then
  if [[ $APPLY -eq 1 ]]; then
    rm -rf "${DST:?}/hooks"
    cp -a "$SRC/hooks" "$DST/hooks"
  fi
  # Count files for summary
  h_count=$(find "$SRC/hooks" -type f | wc -l)
  say "  copied hooks/ tree"
fi

# ── 2. skills (exclude ubiquiti-*) ──────────────────────────────────────────
say "== skills (excluding ubiquiti-*) =="
[[ $APPLY -eq 1 ]] && mkdir -p "$DST/skills"
s_count=0; skip=0
while IFS= read -r skillmd; do
  dir="$(dirname "$skillmd")"
  name="$(basename "$dir")"
  case "$name" in
    ubiquiti-*) skip=$((skip+1)); continue ;;
  esac
  if [[ $APPLY -eq 1 ]]; then
    rm -rf "${DST:?}/skills/$name"
    cp -a "$dir" "$DST/skills/$name"
  fi
  say "  skill: $name"
  s_count=$((s_count+1))
done < <(find "$SRC" -maxdepth 2 -name SKILL.md -not -path '*/.git/*' | sort)

# ── 3. docs/agent-definitions ──────────────────────────────────────────────
say "== docs/agent-definitions =="
d_count=0
if [[ -d "$SRC/docs/agent-definitions" ]]; then
  if [[ $APPLY -eq 1 ]]; then
    rm -rf "${DST:?}/docs/agent-definitions"
    mkdir -p "$DST/docs"
    cp -a "$SRC/docs/agent-definitions" "$DST/docs/"
  fi
  d_count=$(find "$SRC/docs/agent-definitions" -type f 2>/dev/null | wc -l)
  say "  copied docs/agent-definitions/ tree"
fi

# ── 4. registration toolchain (scripts/) ─────────────────────────────────────
say "== scripts =="
sc_count=0
if [[ -d "$SRC/scripts" ]]; then
  if [[ $APPLY -eq 1 ]]; then
    rm -rf "${DST:?}/scripts"
    cp -a "$SRC/scripts" "$DST/"
  fi
  sc_count=$(find "$SRC/scripts" -type f | wc -l)
  say "  copied scripts/ tree"
fi

# ── 5. skills-lock.json ──────────────────────────────────────────────────────
say "== skills-lock.json =="
lock_count=0
if [[ -f "$SRC/skills-lock.json" ]]; then
  [[ $APPLY -eq 1 ]] && cp "$SRC/skills-lock.json" "$DST/skills-lock.json"
  say "  file: skills-lock.json"
  lock_count=1
fi

say ""
say "== summary =="
say "  hooks:                   $h_count files"
say "  scripts:                 $sc_count files"
say "  docs/agent-definitions:  $d_count files"
say "  skills-lock.json:        $lock_count file"
say "  skills:                  $s_count synced, $skip ubiquiti-* excluded"
say ""
if [[ $APPLY -eq 0 ]]; then
  say "DRY RUN — no files written. Re-run with --apply to sync."
else
  say "Applied. Review + commit in dotfiles yourself:"
  say "  cd $(dirname "$DST") && git status"
fi
