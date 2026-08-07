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
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

# ---------- TAP helpers ------------------------------------------------------
plan_count=12
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

# T7-T8: submodule path containing whitespace — parsed correctly, updated.
ws_base="$tmp_dir/ws"
git_q init -b main "$ws_base/subC"
echo one >"$ws_base/subC/file"
git_q -C "$ws_base/subC" add file
git_q -C "$ws_base/subC" commit -m c1
echo two >"$ws_base/subC/file"
git_q -C "$ws_base/subC" commit -am c2
ws_super="$ws_base/super"
git_q init -b main "$ws_super"
git_q -C "$ws_super" commit --allow-empty -m root
git_q -C "$ws_super" submodule add "$ws_base/subC" "mods/sub dir"
git_q -C "$ws_super" commit -m "add submodule with space in path"
c_rec="$(git -C "$ws_super" rev-parse ':mods/sub dir')"
git_q -C "$ws_super/mods/sub dir" checkout "$c_rec~1"
out3="$(run_init_submodules "$ws_super")"
echo "$out3" | sed 's/^/# /'

if [[ "$(git -C "$ws_super/mods/sub dir" rev-parse HEAD)" == "$c_rec" ]]; then
  ok "whitespace-path submodule updated to recorded SHA"
else
  nok "whitespace-path submodule updated to recorded SHA" \
    "HEAD: expected $c_rec, got $(git -C "$ws_super/mods/sub dir" rev-parse HEAD)"
fi
if grep -q '^RC=0$' <<<"$out3"; then
  ok "exits 0 with whitespace submodule path"
else
  nok "exits 0 with whitespace submodule path" "$(grep '^RC=' <<<"$out3")"
fi

# T9-T12: recorded SHA absent locally (superproject advanced past submodule's
# fetched objects). subD additionally has local drift commits -> must be
# skipped (fetch-then-recheck, then ancestry). subE is merely behind -> after
# fetch the ancestry test passes and it must update to the new recorded SHA.
ab_base="$tmp_dir/absent"
for sub in subD subE; do
  git_q init -b main "$ab_base/$sub"
  echo one >"$ab_base/$sub/file"
  git_q -C "$ab_base/$sub" add file
  git_q -C "$ab_base/$sub" commit -m c1
  echo two >"$ab_base/$sub/file"
  git_q -C "$ab_base/$sub" commit -am c2
done
ab_super="$ab_base/super"
git_q init -b main "$ab_super"
git_q -C "$ab_super" commit --allow-empty -m root
git_q -C "$ab_super" submodule add "$ab_base/subD" mods/subD
git_q -C "$ab_super" submodule add "$ab_base/subE" mods/subE
git_q -C "$ab_super" commit -m "add submodules"
# Advance both upstreams to c3; the working submodules have not fetched it.
for sub in subD subE; do
  echo three >"$ab_base/$sub/file"
  git_q -C "$ab_base/$sub" commit -am c3
done
d3="$(git -C "$ab_base/subD" rev-parse HEAD)"
e3="$(git -C "$ab_base/subE" rev-parse HEAD)"
# Record c3 gitlinks in the superproject without touching submodule worktrees.
git_q -C "$ab_super" update-index --add --cacheinfo "160000,$d3,mods/subD"
git_q -C "$ab_super" update-index --add --cacheinfo "160000,$e3,mods/subE"
git_q -C "$ab_super" commit -m "bump gitlinks to c3"
# Drift subD: local commit on top of c2; recorded c3 is absent locally.
echo local >"$ab_super/mods/subD/file"
git_q -C "$ab_super/mods/subD" commit -am local-drift
d_head="$(git -C "$ab_super/mods/subD" rev-parse HEAD)"
out4="$(run_init_submodules "$ab_super")"
echo "$out4" | sed 's/^/# /'

if [[ "$(git -C "$ab_super/mods/subD" rev-parse HEAD)" == "$d_head" ]]; then
  ok "drifted submodule with absent recorded SHA left untouched"
else
  nok "drifted submodule with absent recorded SHA left untouched" \
    "subD HEAD moved: expected $d_head, got $(git -C "$ab_super/mods/subD" rev-parse HEAD)"
fi
if grep -q "mods/subD" <<<"$out4" && grep -q "$d_head" <<<"$out4"; then
  ok "warning names drifted submodule when recorded SHA was absent"
else
  nok "warning names drifted submodule when recorded SHA was absent" \
    "output missing mods/subD or $d_head"
fi
if [[ "$(git -C "$ab_super/mods/subE" rev-parse HEAD)" == "$e3" ]]; then
  ok "behind submodule with absent recorded SHA updated after fetch"
else
  nok "behind submodule with absent recorded SHA updated after fetch" \
    "subE HEAD: expected $e3, got $(git -C "$ab_super/mods/subE" rev-parse HEAD)"
fi
if grep -q '^RC=0$' <<<"$out4"; then
  ok "exits 0 in absent-recorded scenario"
else
  nok "exits 0 in absent-recorded scenario" "$(grep '^RC=' <<<"$out4")"
fi

# ---------- summary ----------------------------------------------------------
echo "# pass=$((n - fail)) fail=$fail"
exit "$fail"
