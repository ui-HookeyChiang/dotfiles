#!/bin/sh
# Helpers to parse worktree paths under <project>/.worktrees/

# wt_rel <project_dir> <path>
# Prints <path> relative to <project_dir>/.worktrees/, rc 1 if outside.
wt_rel() {
  root="$1/.worktrees/"
  p="$2"
  case "$p" in
    "$root"?*) printf '%s\n' "${p#"$root"}"; return 0 ;;
    *) return 1 ;;
  esac
}

# wt_name <rel> — first path segment (worktree namespace/name)
wt_name() {
  printf '%s\n' $1 | cut -d/ -f1
}

# wt_task <rel> — second path segment, empty if absent
wt_task() {
  printf '%s\n' "$1" | cut -d/ -f3 -s
}
