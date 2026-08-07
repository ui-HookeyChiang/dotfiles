#!/usr/bin/env bash
# tests/test-install-submodules.sh — TAP-13 regression suite for init_submodules().
#
# Verifies the submodule drift guard of install.sh's `init_submodules()`:
#   - An initialized submodule whose HEAD has local commits not reachable from
#     the superproject's recorded gitlink (drift) is EXCLUDED from
#     `git submodule update` and a warning names the submodule and both SHAs.
#     This is the regression for nvim losing local commits (<Leader>fw keymap)
#     when install.sh reset a drifted .config/nvim.
#   - A non-drifted initialized submodule (worktree behind the recorded
#     pointer) is still updated to the recorded SHA.
#   - A fresh clone (no submodule initialized) initializes all submodules.
#
# Tests source install.sh in a hermetic subshell (F7 guard prevents main()
# from firing), override note/err/log/run helpers, and call init_submodules
# directly with a tmp $REPO_ROOT that is a real git superproject.
#
# Output: TAP-13. Exit 0 on all pass, non-zero count of failures otherwise.

set -u  # NOT -e: keep running tests after a failure.

# ---------- locate repo ------------------------------------------------------
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
install_sh="$repo_root/install.sh"

tmp_dir="$(mktemp -d -t install-submodules-test.XXXXXX)"
trap 'rm -rf -- "$tmp_dir"' EXIT

# Allow file:// submodule URLs (git >= 2.38 forbids them by default).
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=protocol.file.allow
export GIT_CONFIG_VALUE_0=always
# Hermetic git identity/config.
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test
export HOME_GITCONFIG_UNUSED=1

# ---------- TAP helpers ------------------------------------------------------
plan_count=6
echo "1..$plan_count"
echo "# repo_root=$repo_root"
echo "# tmp_dir=$tmp_dir"

n=0
fail=0

ok() {
  n=$((n + 1))
  printf 'ok %d - %s\n' "$n" "$1"
}

nok() {
  n=$((n + 1))
  fail=$((fail + 1))
  printf 'not ok %d - %s\n' "$n" "$1"
  [[ -n "${2:-}" ]] && printf '# %s\n' "$2"
}

git_q() { git "$@" >/dev/null 2>&1; }

# ---------- fixture ----------------------------------------------------------
# Builds under $1:
#   subA, subB  — upstream repos with 2 commits each
#   super       — superproject recording subA@tip, subB@tip at paths
#                 mods/subA, mods/subB
# Then puts the working tree in the drift scenario:
#   mods/subA: local commit on top of recorded  -> drifted
#   mods/subB: checked out one commit BEHIND recorded -> updatable
# Prints: <super> <subA_recorded> <subA_local_head> <subB_recorded> <subB_old>
make_fixture() {
  local base="$1" sub super
  mkdir -p "$base"
  for sub in subA subB; do
    git_q init -b main "$base/$sub"
    echo one >"$base/$sub/file"
    git_q -C "$base/$sub" add file
    git_q -C "$base/$sub" commit -m c1
    echo two >"$base/$sub/file"
    git_q -C "$base/$sub" commit -am c2
  done
  super="$base/super"
  git_q init -b main "$super"
  git_q -C "$super" commit --allow-empty -m root
  git_q -C "$super" submodule add "$base/subA" mods/subA
  git_q -C "$super" submodule add "$base/subB" mods/subB
  git_q -C "$super" commit -m "add submodules"

  local a_rec b_rec a_head b_old
  a_rec="$(git -C "$super" rev-parse :mods/subA)"
  b_rec="$(git -C "$super" rev-parse :mods/subB)"
  # Drift subA: local commit not reachable from recorded pointer.
  echo local >"$super/mods/subA/file"
  git_q -C "$super/mods/subA" commit -am local-drift
  a_head="$(git -C "$super/mods/subA" rev-parse HEAD)"
  # Rewind subB one commit behind recorded (HEAD is ancestor of recorded).
  git_q -C "$super/mods/subB" checkout "$b_rec~1"
  b_old="$(git -C "$super/mods/subB" rev-parse HEAD)"

  printf '%s %s %s %s %s\n' "$super" "$a_rec" "$a_head" "$b_rec" "$b_old"
}

# Run init_submodules in a hermetic subshell against $1 as REPO_ROOT.
# Captures stdout+stderr; last line is RC=N.
run_init_submodules() {
  local repo="$1"
  bash -c '
    install_sh="$1"; repo="$2"
    # shellcheck disable=SC1090
    . "$install_sh"
    set +eu
    trap - ERR
    log()  { :; }
    note() { printf "NOTE: %s\n" "$*"; }
    err()  { printf "ERR: %s\n"  "$*"; }
    run()  { "$@"; }
    REPO_ROOT="$repo"
    DRY_RUN=0
    init_submodules
    printf "RC=%d\n" $?
  ' _ "$install_sh" "$repo" 2>&1
}

# ---------- tests ------------------------------------------------------------

# T1-T4: drift scenario — subA drifted, subB behind.
read -r super a_rec a_head b_rec b_old < <(make_fixture "$tmp_dir/drift")
out="$(run_init_submodules "$super")"
echo "$out" | sed 's/^/# /'

# T1: drifted subA working tree untouched (HEAD keeps the local commit).
if [[ "$(git -C "$super/mods/subA" rev-parse HEAD)" == "$a_head" ]]; then
  ok "drifted submodule left untouched (regression)"
else
  nok "drifted submodule left untouched (regression)" \
    "subA HEAD moved: expected $a_head, got $(git -C "$super/mods/subA" rev-parse HEAD)"
fi

# T2: warning names the submodule and both SHAs.
if grep -q "mods/subA" <<<"$out" && grep -q "$a_head" <<<"$out" && grep -q "$a_rec" <<<"$out"; then
  ok "warning names drifted submodule and both SHAs"
else
  nok "warning names drifted submodule and both SHAs" "output missing path or SHA"
fi

# T3: non-drifted subB updated to the recorded pointer.
if [[ "$(git -C "$super/mods/subB" rev-parse HEAD)" == "$b_rec" ]]; then
  ok "non-drifted submodule updated to recorded SHA"
else
  nok "non-drifted submodule updated to recorded SHA" \
    "subB HEAD: expected $b_rec, got $(git -C "$super/mods/subB" rev-parse HEAD)"
fi

# T4: init_submodules exits 0 despite the skipped submodule.
if grep -q '^RC=0$' <<<"$out"; then
  ok "exits 0 when a drifted submodule is skipped"
else
  nok "exits 0 when a drifted submodule is skipped" "$(grep '^RC=' <<<"$out")"
fi

# T5-T6: fresh clone — no submodule initialized; all must init.
read -r super2 a_rec2 _ b_rec2 _ < <(make_fixture "$tmp_dir/fresh")
git_q clone "$super2" "$tmp_dir/fresh-clone"
out2="$(run_init_submodules "$tmp_dir/fresh-clone")"
echo "$out2" | sed 's/^/# /'

if [[ "$(git -C "$tmp_dir/fresh-clone/mods/subA" rev-parse HEAD 2>/dev/null)" == "$a_rec2" ]]; then
  ok "fresh clone initializes first submodule"
else
  nok "fresh clone initializes first submodule" "subA not at $a_rec2"
fi
if [[ "$(git -C "$tmp_dir/fresh-clone/mods/subB" rev-parse HEAD 2>/dev/null)" == "$b_rec2" ]]; then
  ok "fresh clone initializes second submodule"
else
  nok "fresh clone initializes second submodule" "subB not at $b_rec2"
fi

# ---------- summary ----------------------------------------------------------
echo "# pass=$((n - fail)) fail=$fail"
exit "$fail"
