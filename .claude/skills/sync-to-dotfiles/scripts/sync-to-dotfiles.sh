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

# ── 1. hooks/*.sh ───────────────────────────────────────────────────────────
say "== hooks =="
[[ $APPLY -eq 1 ]] && mkdir -p "$DST/hooks"
h_count=0
for f in "$SRC"/hooks/*.sh; do
  [[ -e "$f" ]] || continue
  base="$(basename "$f")"
  [[ $APPLY -eq 1 ]] && cp "$f" "$DST/hooks/$base"
  say "  hook: $base"
  h_count=$((h_count+1))
done
# hook tests too, if present
if [[ -d "$SRC/hooks/tests" ]]; then
  [[ $APPLY -eq 1 ]] && { mkdir -p "$DST/hooks/tests"; cp "$SRC"/hooks/tests/*.sh "$DST/hooks/tests/" 2>/dev/null || true; }
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

# ── 3. docs/agents ──────────────────────────────────────────────────────────
say "== docs/agents =="
d_count=0
if [[ -d "$SRC/docs/agents" ]]; then
  [[ $APPLY -eq 1 ]] && mkdir -p "$DST/docs/agents"
  while IFS= read -r f; do
    rel="${f#"$SRC"/docs/agents/}"
    if [[ $APPLY -eq 1 ]]; then
      mkdir -p "$DST/docs/agents/$(dirname "$rel")"
      cp "$f" "$DST/docs/agents/$rel"
    fi
    say "  doc: $rel"
    d_count=$((d_count+1))
  done < <(find "$SRC/docs/agents" -type f | sort)
fi

say ""
say "== summary =="
say "  hooks:       $h_count"
say "  skills:      $s_count synced, $skip ubiquiti-* excluded"
say "  docs/agents: $d_count"
say ""
if [[ $APPLY -eq 0 ]]; then
  say "DRY RUN — no files written. Re-run with --apply to sync."
else
  say "Applied. Review + commit in dotfiles yourself:"
  say "  cd $(dirname "$DST") && git status"
fi
