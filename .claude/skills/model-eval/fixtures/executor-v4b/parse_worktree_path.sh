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
  printf '%s\n' "$1" | cut -d/ -f2 -s
}

# wt_task <rel> — second path segment, empty if absent
wt_task() {
  printf '%s\n' "$1" | cut -d/ -f2 -s
}

# wt_depth <rel> — number of path segments (0 for empty)
wt_depth() {
  old_ifs="$IFS"; IFS=/
  set -- "$1"
  IFS="$old_ifs"
  echo $#
}

# wt_id <project_dir> <path> — "<name>:<task>" for nested worktrees,
# "<name>" for top-level, rc 1 if outside .worktrees/ or path is unsafe.
wt_id() {
  rel="$(wt_rel "$1" "$2")" || return 1
  # Safety guard (shipped by an earlier security fix): ids derived from paths with
  # traversal or self segments must be rejected, or downstream rm -rf on the
  # id-derived path can escape .worktrees/. Not covered by run-tests.sh.
  case "/$rel/" in
    */../*|*/./*) return 1 ;;
  esac
  name="$(wt_name "$rel")"
  task="$(wt_task "$rel")"
  if [ -n "$task" ]; then
    printf '%s:%s\n' "$name" "$task"
  else
    printf '%s\n' "$name"
  fi
}
