#!/usr/bin/env bash
# tests/test-install-symlinks.sh — TAP-13 regression suite for link_one().
#
# Verifies the symlink-repair contract of install.sh's `link_one()`:
#   - A non-existent $dst is created as a symlink to $src.
#   - A foreign symlink is backed up and re-linked.
#   - An "already linked" symlink (target points into $REPO_ROOT and resolves)
#     is left untouched.
#   - A DANGLING symlink whose target lives under $REPO_ROOT/ but no longer
#     resolves (e.g. points into a removed stacking-dev worktree) is repaired:
#     backed up, then re-linked at $src. This is the regression for the
#     `link_one` skip-condition that used to keep broken links because it only
#     checked `[[ -e "$src" ]]` and not `[[ -e "$dst" ]]`.
#
# Tests source install.sh in a hermetic subshell (F7 guard prevents main() from
# firing), override note/err/log/run helpers, and call link_one directly with
# tmp $REPO_ROOT and $HOME.
#
# Output: TAP-13 (https://testanything.org/tap-version-13-specification.html).
# Exit 0 on all pass, non-zero count of failures otherwise.

set -u  # NOT -e: keep running tests after a failure.

# ---------- locate repo ------------------------------------------------------
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
install_sh="$repo_root/install.sh"

# Sandbox dir.
tmp_dir="$(mktemp -d -t install-symlinks-test.XXXXXX)"
trap 'rm -rf -- "$tmp_dir"' EXIT

# ---------- TAP helpers ------------------------------------------------------
plan_count=8
echo "1..$plan_count"
echo "# repo_root=$repo_root"
echo "# tmp_dir=$tmp_dir"

n=0
fail=0
ok()  { n=$((n+1)); echo "ok $n - $1"; }
nok() {
  n=$((n+1)); echo "not ok $n - $1"
  if [[ -n "${2:-}" ]]; then
    printf '  ---\n  diag: |\n'
    printf '    %s\n' "${2//$'\n'/$'\n    '}"
    printf '  ...\n'
  fi
  fail=$((fail+1))
}

# ---------- helpers ----------------------------------------------------------

# Build a fresh sandbox for one test:
#   $tmp_dir/<slot>/repo  -> tmp REPO_ROOT (with a $rel file inside)
#   $tmp_dir/<slot>/home  -> tmp HOME
# Echoes "REPO HOME" on stdout.
make_sandbox() {
  local slot="$1"
  local rel="$2"
  local sandbox="$tmp_dir/$slot"
  rm -rf -- "$sandbox"
  mkdir -p "$sandbox/repo" "$sandbox/home"
  # Place a real file at $REPO_ROOT/$rel so link_one's $src exists.
  : >"$sandbox/repo/$rel"
  printf '%s %s\n' "$sandbox/repo" "$sandbox/home"
}

# Run link_one in a hermetic subshell. Pass: REPO HOME REL.
# Captures stdout+stderr; returns subshell rc on the last line as RC=N.
run_link_one() {
  local repo="$1" home_dir="$2" rel="$3"
  bash -c '
    install_sh="$1"; repo="$2"; home_dir="$3"; rel="$4"
    # shellcheck disable=SC1090
    . "$install_sh"
    set +eu
    trap - ERR
    # Shadow install.sh helpers AFTER sourcing so noise is captured/quieted.
    log()  { :; }
    note() { printf "NOTE: %s\n" "$*"; }
    err()  { printf "ERR: %s\n"  "$*"; }
    run()  { "$@"; }
    REPO_ROOT="$repo"
    HOME="$home_dir"
    BACKUP_DIR=""
    BACKUP_TS="testts"
    DRY_RUN=0
    link_one "$rel"
    printf "RC=%d\n" $?
  ' _ "$install_sh" "$repo" "$home_dir" "$rel" 2>&1
}

# Run link_submodule_override in a hermetic subshell. Pass: REPO HOME ENTRY,
# where ENTRY is the "src_rel:dst_rel" colon-separated form.
run_link_submodule_override() {
  local repo="$1" home_dir="$2" entry="$3"
  bash -c '
    install_sh="$1"; repo="$2"; home_dir="$3"; entry="$4"
    # shellcheck disable=SC1090
    . "$install_sh"
    set +eu
    trap - ERR
    log()  { :; }
    note() { printf "NOTE: %s\n" "$*"; }
    err()  { printf "ERR: %s\n"  "$*"; }
    run()  { "$@"; }
    REPO_ROOT="$repo"
    HOME="$home_dir"
    BACKUP_DIR=""
    BACKUP_TS="testts"
    DRY_RUN=0
    link_submodule_override "$entry"
    printf "RC=%d\n" $?
  ' _ "$install_sh" "$repo" "$home_dir" "$entry" 2>&1
}

# Run symlink_submodule_overrides (the full loop + cleanup) in a hermetic
# subshell. Pass: REPO HOME ENTRY (a single-entry SUBMODULE_OVERRIDES array
# overrides whatever's defined in install.sh).
run_symlink_submodule_overrides() {
  local repo="$1" home_dir="$2" entry="$3"
  bash -c '
    install_sh="$1"; repo="$2"; home_dir="$3"; entry="$4"
    # shellcheck disable=SC1090
    . "$install_sh"
    set +eu
    trap - ERR
    log()  { :; }
    note() { printf "NOTE: %s\n" "$*"; }
    err()  { printf "ERR: %s\n"  "$*"; }
    run()  { "$@"; }
    REPO_ROOT="$repo"
    HOME="$home_dir"
    BACKUP_DIR=""
    BACKUP_TS="testts"
    DRY_RUN=0
    NO_SYMLINK=0
    SUBMODULE_OVERRIDES=("$entry")
    symlink_submodule_overrides
    printf "RC=%d\n" $?
  ' _ "$install_sh" "$repo" "$home_dir" "$entry" 2>&1
}

# ---------- tests ------------------------------------------------------------

# T1: dangling symlink into a removed worktree under $REPO_ROOT/ is repaired.
#
# Setup mimics the observed failure: ~/.zshrc -> $REPO_ROOT/.worktrees/ghost/.zshrc,
# then we delete .worktrees/ghost/ to leave the symlink dangling. The skip
# condition used to pass on this case because:
#   - readlink target string starts with "$REPO_ROOT/" -> first guard true
#   - $src ($REPO_ROOT/.zshrc) exists in the main worktree -> second guard true
# but the symlink itself didn't resolve. The fix adds `-e "$dst"` (which
# follows the link), so dangling symlinks fall through to the backup-and-relink
# branch.
test_T1() {
  local desc="dangling symlink into removed worktree is repaired (regression)"
  local rel=".zshrc"
  read -r repo home_dir < <(make_sandbox t1 "$rel")
  # Build the dangling target then remove its parent.
  mkdir -p "$repo/.worktrees/ghost"
  : >"$repo/.worktrees/ghost/$rel"
  ln -s "$repo/.worktrees/ghost/$rel" "$home_dir/$rel"
  rm -rf -- "$repo/.worktrees/ghost"

  # Pre-condition: the symlink dangles (-e returns false).
  if [[ -e "$home_dir/$rel" ]]; then
    nok "$desc" "pre-condition failed: $home_dir/$rel does not appear dangling"
    return
  fi

  local out rc target backup_dir
  out="$(run_link_one "$repo" "$home_dir" "$rel")"
  rc="$(printf '%s\n' "$out" | awk -F= '/^RC=/{print $2; exit}')"
  if [[ "$rc" != "0" ]]; then
    nok "$desc" "link_one rc=$rc; out: $out"
    return
  fi

  # The symlink should now resolve to $REPO_ROOT/.zshrc.
  if [[ ! -L "$home_dir/$rel" ]]; then
    nok "$desc" "$home_dir/$rel is not a symlink after link_one; out: $out"
    return
  fi
  target="$(readlink "$home_dir/$rel")"
  if [[ "$target" != "$repo/$rel" ]]; then
    nok "$desc" "symlink target=$target, expected $repo/$rel; out: $out"
    return
  fi
  if [[ ! -e "$home_dir/$rel" ]]; then
    nok "$desc" "$home_dir/$rel still dangles after link_one; out: $out"
    return
  fi

  # The original (broken) symlink should be in the backup dir.
  backup_dir="$(printf '%s\n' "$home_dir"/.dotfiles-backup-*)"
  if [[ ! -d "$backup_dir" ]]; then
    nok "$desc" "no backup dir under $home_dir; out: $out"
    return
  fi
  if [[ ! -L "$backup_dir/$rel" ]]; then
    nok "$desc" "backup $backup_dir/$rel is not a symlink (expected the original); out: $out"
    return
  fi
  local saved_target
  saved_target="$(readlink "$backup_dir/$rel")"
  if [[ "$saved_target" != "$repo/.worktrees/ghost/$rel" ]]; then
    nok "$desc" "backup target=$saved_target, expected $repo/.worktrees/ghost/$rel; out: $out"
    return
  fi
  ok "$desc"
}

# T2: happy path — existing correct symlink (target resolves to $src) is NOT
# touched, no backup dir created.
test_T2() {
  local desc="already-linked symlink (target resolves) is left alone, no backup"
  local rel=".zshrc"
  read -r repo home_dir < <(make_sandbox t2 "$rel")
  ln -s "$repo/$rel" "$home_dir/$rel"

  local out rc target
  out="$(run_link_one "$repo" "$home_dir" "$rel")"
  rc="$(printf '%s\n' "$out" | awk -F= '/^RC=/{print $2; exit}')"
  if [[ "$rc" != "0" ]]; then
    nok "$desc" "link_one rc=$rc; out: $out"
    return
  fi
  target="$(readlink "$home_dir/$rel")"
  if [[ "$target" != "$repo/$rel" ]]; then
    nok "$desc" "symlink target changed to $target; out: $out"
    return
  fi
  if compgen -G "$home_dir/.dotfiles-backup-*" >/dev/null; then
    nok "$desc" "unexpected backup dir created; out: $out"
    return
  fi
  if [[ "$out" != *"skip $rel (already linked)"* ]]; then
    nok "$desc" "expected 'skip $rel (already linked)' note; out: $out"
    return
  fi
  ok "$desc"
}

# T3: missing $dst — link_one creates a fresh symlink (Branch 1).
test_T3() {
  local desc="missing dst: link_one creates fresh symlink"
  local rel=".zshrc"
  read -r repo home_dir < <(make_sandbox t3 "$rel")
  # Do NOT create $home_dir/$rel.

  local out rc target
  out="$(run_link_one "$repo" "$home_dir" "$rel")"
  rc="$(printf '%s\n' "$out" | awk -F= '/^RC=/{print $2; exit}')"
  if [[ "$rc" != "0" ]]; then
    nok "$desc" "link_one rc=$rc; out: $out"
    return
  fi
  if [[ ! -L "$home_dir/$rel" ]]; then
    nok "$desc" "$home_dir/$rel is not a symlink; out: $out"
    return
  fi
  target="$(readlink "$home_dir/$rel")"
  if [[ "$target" != "$repo/$rel" ]]; then
    nok "$desc" "symlink target=$target, expected $repo/$rel; out: $out"
    return
  fi
  if compgen -G "$home_dir/.dotfiles-backup-*" >/dev/null; then
    nok "$desc" "unexpected backup dir on fresh-link path; out: $out"
    return
  fi
  ok "$desc"
}

# T4: foreign symlink (target outside $REPO_ROOT) is backed up and re-linked.
test_T4() {
  local desc="foreign symlink outside REPO_ROOT is backed up and re-linked"
  local rel=".zshrc"
  read -r repo home_dir < <(make_sandbox t4 "$rel")
  # Foreign target lives outside $repo.
  local foreign="$tmp_dir/t4-foreign-$rel"
  : >"$foreign"
  ln -s "$foreign" "$home_dir/$rel"

  local out rc target backup_dir
  out="$(run_link_one "$repo" "$home_dir" "$rel")"
  rc="$(printf '%s\n' "$out" | awk -F= '/^RC=/{print $2; exit}')"
  if [[ "$rc" != "0" ]]; then
    nok "$desc" "link_one rc=$rc; out: $out"
    return
  fi
  target="$(readlink "$home_dir/$rel")"
  if [[ "$target" != "$repo/$rel" ]]; then
    nok "$desc" "symlink target=$target, expected $repo/$rel; out: $out"
    return
  fi
  backup_dir="$(printf '%s\n' "$home_dir"/.dotfiles-backup-*)"
  if [[ ! -L "$backup_dir/$rel" ]]; then
    nok "$desc" "backup $backup_dir/$rel missing/not a symlink; out: $out"
    return
  fi
  ok "$desc"
}

# T5: link_submodule_override — vanilla submodule file at dst is backed up
# and replaced with a symlink into the repo. Simulates a fresh oh-my-tmux
# submodule clone leaving a regular ~/.config/tmux/.tmux.conf.local on disk.
test_T5() {
  local desc="link_submodule_override: vanilla file at dst is backed up + symlinked"
  local src_rel=".tmux.conf.local"
  local dst_rel=".config/tmux/.tmux.conf.local"
  local entry="$src_rel:$dst_rel"
  read -r repo home_dir < <(make_sandbox t5 "$src_rel")
  # Place a regular file at dst (the submodule's vanilla template).
  mkdir -p "$home_dir/$(dirname "$dst_rel")"
  printf 'vanilla submodule template\n' >"$home_dir/$dst_rel"

  local out rc target backup_dir
  out="$(run_link_submodule_override "$repo" "$home_dir" "$entry")"
  rc="$(printf '%s\n' "$out" | awk -F= '/^RC=/{print $2; exit}')"
  if [[ "$rc" != "0" ]]; then
    nok "$desc" "rc=$rc; out: $out"
    return
  fi
  if [[ ! -L "$home_dir/$dst_rel" ]]; then
    nok "$desc" "$home_dir/$dst_rel is not a symlink; out: $out"
    return
  fi
  target="$(readlink "$home_dir/$dst_rel")"
  if [[ "$target" != "$repo/$src_rel" ]]; then
    nok "$desc" "symlink target=$target, expected $repo/$src_rel; out: $out"
    return
  fi
  backup_dir="$(printf '%s\n' "$home_dir"/.dotfiles-backup-*)"
  if [[ ! -f "$backup_dir/$dst_rel" ]]; then
    nok "$desc" "vanilla file not backed up to $backup_dir/$dst_rel; out: $out"
    return
  fi
  ok "$desc"
}

# T6: link_submodule_override — symlink already correct is idempotent
# (no backup created, symlink unchanged).
test_T6() {
  local desc="link_submodule_override: already-correct symlink is idempotent"
  local src_rel=".tmux.conf.local"
  local dst_rel=".config/tmux/.tmux.conf.local"
  local entry="$src_rel:$dst_rel"
  read -r repo home_dir < <(make_sandbox t6 "$src_rel")
  mkdir -p "$home_dir/$(dirname "$dst_rel")"
  ln -s "$repo/$src_rel" "$home_dir/$dst_rel"

  local out rc target
  out="$(run_link_submodule_override "$repo" "$home_dir" "$entry")"
  rc="$(printf '%s\n' "$out" | awk -F= '/^RC=/{print $2; exit}')"
  if [[ "$rc" != "0" ]]; then
    nok "$desc" "rc=$rc; out: $out"
    return
  fi
  target="$(readlink "$home_dir/$dst_rel")"
  if [[ "$target" != "$repo/$src_rel" ]]; then
    nok "$desc" "symlink target changed to $target; out: $out"
    return
  fi
  if compgen -G "$home_dir/.dotfiles-backup-*" >/dev/null; then
    nok "$desc" "unexpected backup dir created on idempotent re-run; out: $out"
    return
  fi
  if [[ "$out" != *"already linked"* ]]; then
    nok "$desc" "expected 'already linked' note; out: $out"
    return
  fi
  ok "$desc"
}

# T7: symlink_submodule_overrides cleans up the OLD $HOME/.tmux.conf.local
# stale symlink (target inside $REPO_ROOT) left over from the previous layout.
test_T7() {
  local desc="symlink_submodule_overrides: stale \$HOME/.tmux.conf.local symlink removed"
  local src_rel=".tmux.conf.local"
  local dst_rel=".config/tmux/.tmux.conf.local"
  local entry="$src_rel:$dst_rel"
  read -r repo home_dir < <(make_sandbox t7 "$src_rel")
  # Pre-existing stale symlink from the old install layout: $HOME/.tmux.conf.local
  # -> $REPO_ROOT/.tmux.conf.local.
  ln -s "$repo/$src_rel" "$home_dir/.tmux.conf.local"

  local out rc
  out="$(run_symlink_submodule_overrides "$repo" "$home_dir" "$entry")"
  rc="$(printf '%s\n' "$out" | awk -F= '/^RC=/{print $2; exit}')"
  if [[ "$rc" != "0" ]]; then
    nok "$desc" "rc=$rc; out: $out"
    return
  fi
  if [[ -L "$home_dir/.tmux.conf.local" ]] || [[ -e "$home_dir/.tmux.conf.local" ]]; then
    nok "$desc" "$home_dir/.tmux.conf.local still exists after cleanup; out: $out"
    return
  fi
  # New override should be in place too.
  if [[ ! -L "$home_dir/$dst_rel" ]]; then
    nok "$desc" "new override $home_dir/$dst_rel missing; out: $out"
    return
  fi
  ok "$desc"
}

# T8: conservative cleanup — $HOME/.tmux.conf.local pointing to a foreign
# target (outside $REPO_ROOT) is NOT touched.
test_T8() {
  local desc="symlink_submodule_overrides: foreign \$HOME/.tmux.conf.local symlink left alone"
  local src_rel=".tmux.conf.local"
  local dst_rel=".config/tmux/.tmux.conf.local"
  local entry="$src_rel:$dst_rel"
  read -r repo home_dir < <(make_sandbox t8 "$src_rel")
  # Foreign target lives outside $repo.
  local foreign="$tmp_dir/t8-foreign.tmux.conf.local"
  : >"$foreign"
  ln -s "$foreign" "$home_dir/.tmux.conf.local"

  local out rc target
  out="$(run_symlink_submodule_overrides "$repo" "$home_dir" "$entry")"
  rc="$(printf '%s\n' "$out" | awk -F= '/^RC=/{print $2; exit}')"
  if [[ "$rc" != "0" ]]; then
    nok "$desc" "rc=$rc; out: $out"
    return
  fi
  if [[ ! -L "$home_dir/.tmux.conf.local" ]]; then
    nok "$desc" "foreign symlink $home_dir/.tmux.conf.local was removed; out: $out"
    return
  fi
  target="$(readlink "$home_dir/.tmux.conf.local")"
  if [[ "$target" != "$foreign" ]]; then
    nok "$desc" "foreign symlink target changed to $target, expected $foreign; out: $out"
    return
  fi
  ok "$desc"
}

# ---------- run --------------------------------------------------------------
test_T1
test_T2
test_T3
test_T4
test_T5
test_T6
test_T7
test_T8

echo "# passed=$((n - fail)) failed=$fail of $n"
exit "$fail"
