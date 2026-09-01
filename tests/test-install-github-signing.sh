#!/usr/bin/env bash
# tests/test-install-github-signing.sh — TAP-13 for setup_github_ssh_signing().
#
# Seams: local key/config/allowed_signers writes, and GitHub upload gated on
# HOME==REAL_HOME. Tests never hit the real GitHub API (fake gh on PATH, or
# HOME != REAL_HOME).
#
# Output: TAP-13. Exit 0 on all pass.

set -u

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
install_sh="$repo_root/install.sh"

tmp_dir="$(mktemp -d -t install-github-signing-test.XXXXXX)"
trap 'rm -rf -- "$tmp_dir"' EXIT

plan_count=8
echo "1..$plan_count"
echo "# repo_root=$repo_root"

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

# Run setup_github_ssh_signing in a hermetic HOME. Extra env assignments
# after HOME= are optional (e.g. REAL_HOME=... PATH=...).
run_setup() {
  local home_dir="$1"
  shift
  bash -c '
    install_sh="$1"; home_dir="$2"; shift 2
    # shellcheck disable=SC1090
    . "$install_sh"
    set +eu
    trap - ERR
    log()  { :; }
    note() { printf "NOTE: %s\n" "$*"; }
    err()  { printf "ERR: %s\n"  "$*"; }
    run()  { "$@"; }
    HOME="$home_dir"
    DRY_RUN=0
    for kv in "$@"; do
      export "$kv"
    done
    setup_github_ssh_signing
    printf "RC=%d\n" $?
  ' _ "$install_sh" "$home_dir" "$@" 2>&1
}

make_home() {
  local slot="$1"
  local h="$tmp_dir/$slot"
  rm -rf -- "$h"
  mkdir -p "$h"
  printf '%s\n' "$h"
}

# T1: missing key -> generates ed25519 pair
test_T1() {
  local desc="generates ~/.ssh/id_ed25519_github when missing"
  local home_dir out
  home_dir="$(make_home t1)"
  out="$(run_setup "$home_dir")"
  if [[ -f "$home_dir/.ssh/id_ed25519_github" && -f "$home_dir/.ssh/id_ed25519_github.pub" ]] \
     && grep -q '^ssh-ed25519 ' "$home_dir/.ssh/id_ed25519_github.pub"; then
    ok "$desc"
  else
    nok "$desc" "$out"
  fi
}

# T2: existing key is left untouched
test_T2() {
  local desc="does not overwrite an existing github ssh key"
  local home_dir before after out
  home_dir="$(make_home t2)"
  mkdir -p "$home_dir/.ssh"
  ssh-keygen -t ed25519 -f "$home_dir/.ssh/id_ed25519_github" -C keep-me -N "" -q
  before="$(cat "$home_dir/.ssh/id_ed25519_github.pub")"
  out="$(run_setup "$home_dir")"
  after="$(cat "$home_dir/.ssh/id_ed25519_github.pub")"
  if [[ "$before" == "$after" ]]; then
    ok "$desc"
  else
    nok "$desc" "before=$before after=$after out=$out"
  fi
}

# T3: missing ssh config -> Host github.com block
test_T3() {
  local desc="writes Host github.com when ssh config is missing"
  local home_dir out
  home_dir="$(make_home t3)"
  out="$(run_setup "$home_dir")"
  if grep -qE '^Host[[:space:]]+github\.com' "$home_dir/.ssh/config" \
     && grep -q 'IdentityFile ~/.ssh/id_ed25519_github' "$home_dir/.ssh/config"; then
    ok "$desc"
  else
    nok "$desc" "$out$(printf '\n')$(cat "$home_dir/.ssh/config" 2>/dev/null || true)"
  fi
}

# T4: existing Host github.com is not rewritten
test_T4() {
  local desc="leaves an existing Host github.com block alone"
  local home_dir before after out
  home_dir="$(make_home t4)"
  mkdir -p "$home_dir/.ssh"
  ssh-keygen -t ed25519 -f "$home_dir/.ssh/id_ed25519_github" -C keep -N "" -q
  cat > "$home_dir/.ssh/config" <<'EOF'
Host github.com
  IdentityFile ~/.ssh/other_key
EOF
  before="$(cat "$home_dir/.ssh/config")"
  out="$(run_setup "$home_dir")"
  after="$(cat "$home_dir/.ssh/config")"
  if [[ "$before" == "$after" ]]; then
    ok "$desc"
  else
    nok "$desc" "after=$after out=$out"
  fi
}

# T5: allowed_signers gets the pubkey blob
test_T5() {
  local desc="appends pubkey blob to ~/.git_allowed_signers"
  local home_dir blob out
  home_dir="$(make_home t5)"
  out="$(run_setup "$home_dir")"
  blob="$(awk '{print $2}' "$home_dir/.ssh/id_ed25519_github.pub")"
  if grep -qF "$blob" "$home_dir/.git_allowed_signers" \
     && grep -q '^hookey.chiang@gmail.com ' "$home_dir/.git_allowed_signers"; then
    ok "$desc"
  else
    nok "$desc" "$out$(printf '\n')$(cat "$home_dir/.git_allowed_signers" 2>/dev/null || true)"
  fi
}

# T6: allowed_signers is not duplicated
test_T6() {
  local desc="does not duplicate an allowed_signers line"
  local home_dir blob count out
  home_dir="$(make_home t6)"
  mkdir -p "$home_dir/.ssh"
  ssh-keygen -t ed25519 -f "$home_dir/.ssh/id_ed25519_github" -C keep -N "" -q
  blob="$(awk '{print $2}' "$home_dir/.ssh/id_ed25519_github.pub")"
  printf 'hookey.chiang@gmail.com ssh-ed25519 %s existing\n' "$blob" > "$home_dir/.git_allowed_signers"
  out="$(run_setup "$home_dir")"
  count="$(grep -cF "$blob" "$home_dir/.git_allowed_signers" || true)"
  if [[ "$count" == "1" ]]; then
    ok "$desc"
  else
    nok "$desc" "count=$count out=$out"
  fi
}

# T7: HOME != REAL_HOME never invokes gh
test_T7() {
  local desc="skips GitHub upload when HOME != REAL_HOME"
  local home_dir bindir out
  home_dir="$(make_home t7)"
  bindir="$tmp_dir/t7-bin"
  mkdir -p "$bindir"
  cat > "$bindir/gh" <<'EOF'
#!/bin/sh
echo "gh-called $*" >> "${GH_LOG:?}"
exit 0
EOF
  chmod +x "$bindir/gh"
  : > "$tmp_dir/t7-gh.log"
  out="$(run_setup "$home_dir" "PATH=$bindir:$PATH" "GH_LOG=$tmp_dir/t7-gh.log")"
  if [[ ! -s "$tmp_dir/t7-gh.log" ]] && grep -q 'HOME!=REAL_HOME' <<<"$out"; then
    ok "$desc"
  else
    nok "$desc" "log=$(cat "$tmp_dir/t7-gh.log") out=$out"
  fi
}

# T8: HOME==REAL_HOME + fake gh registers auth and signing when list is empty
test_T8() {
  local desc="registers authentication and signing keys via gh when list is empty"
  local home_dir bindir out
  home_dir="$(make_home t8)"
  bindir="$tmp_dir/t8-bin"
  mkdir -p "$bindir"
  cat > "$bindir/gh" <<EOF
#!/bin/sh
echo "gh \$*" >> "$tmp_dir/t8-gh.log"
case " \$* " in
  *" auth status "*) exit 0 ;;
  *" ssh-key list "*) exit 0 ;;
  *" ssh-key add "*) echo "\$*" >> "$tmp_dir/t8-add.log"; exit 0 ;;
esac
exit 1
EOF
  chmod +x "$bindir/gh"
  : > "$tmp_dir/t8-gh.log"
  : > "$tmp_dir/t8-add.log"
  out="$(run_setup "$home_dir" "PATH=$bindir:/usr/bin:/bin" "REAL_HOME=$home_dir")"
  if grep -q -- '--type authentication' "$tmp_dir/t8-add.log" \
     && grep -q -- '--type signing' "$tmp_dir/t8-add.log"; then
    ok "$desc"
  else
    nok "$desc" "add=$(cat "$tmp_dir/t8-add.log") log=$(cat "$tmp_dir/t8-gh.log") out=$out"
  fi
}

test_T1
test_T2
test_T3
test_T4
test_T5
test_T6
test_T7
test_T8

if (( n != plan_count )); then
  echo "# planned $plan_count tests, ran $n" >&2
  exit 1
fi
exit "$fail"
