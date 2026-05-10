#!/usr/bin/env bash
# tests/test-zsh-init.sh — integration tests for zsh init behavior.
#
# Verifies that the dotfiles in this repo correctly propagate environment
# (EDITOR, PATH, DEBEMAIL, aliases, etc.) across all zsh invocation modes:
#   * non-login non-interactive   (zsh -c)
#   * non-login interactive       (zsh -ic)
#   * login interactive           (zsh -lic)
#
# This is the regression class fixed by PR-9 (.zshenv introduction).
#
# By default the tests target the repo via ZDOTDIR override, so they run
# correctly even before `bash install.sh` has deployed the dotfiles to $HOME.
# Pass --installed to instead probe the user's installed dotfiles via $HOME.
#
# Output: TAP-13 (https://testanything.org/tap-version-13-specification.html).
# Exit 0 on all pass, non-zero count of failures otherwise.

set -u  # NOT -e: we want to keep running tests after a failure.

# ---------- locate repo ------------------------------------------------------
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

# ---------- mode -------------------------------------------------------------
mode="repo"  # "repo" (ZDOTDIR override, default) or "installed" ($HOME)
for arg in "$@"; do
  case "$arg" in
    --installed) mode="installed" ;;
    --repo)      mode="repo" ;;
    -h|--help)
      cat <<'USAGE'
Usage: test-zsh-init.sh [--repo|--installed]

  --repo       (default) test repo dotfiles via ZDOTDIR override.
               Works regardless of deployment state.
  --installed  test the user's installed dotfiles via $HOME.
               Requires `bash install.sh` to have been run.
USAGE
      exit 0
      ;;
  esac
done

# Sandbox dir for compdump etc. so spawned zsh shells don't pollute the repo.
tmp_dir="$(mktemp -d -t zsh-init-test.XXXXXX)"
trap 'rm -rf -- "$tmp_dir"' EXIT

if [[ "$mode" == "installed" ]]; then
  if [[ ! -L "$HOME/.zshenv" ]] || [[ "$(readlink -- "$HOME/.zshenv")" != *"/dotfiles/.zshenv" ]]; then
    echo "1..0 # SKIP --installed mode requires \`bash install.sh\` (\$HOME/.zshenv is not a symlink to dotfiles)"
    exit 0
  fi
  zsh_env=(env)
else
  # In repo mode, point ZDOTDIR at $tmp_dir with symlinks to the repo's
  # zsh files. This makes zsh source our .zshenv/.zshrc/.zprofile while
  # writing .zcompdump and any other ZDOTDIR-relative state into $tmp_dir.
  for f in .zshenv .zshrc .zprofile .p10k.zsh; do
    [[ -e "$repo_root/$f" ]] && ln -s "$repo_root/$f" "$tmp_dir/$f"
  done
  zsh_env=(env "ZDOTDIR=$tmp_dir")
fi

# zrun: invoke zsh with the chosen environment. All args are forwarded to zsh.
zrun() { "${zsh_env[@]}" zsh "$@"; }

# ---------- TAP helpers ------------------------------------------------------
plan_count=10
echo "1..$plan_count"
echo "# mode: $mode (repo_root=$repo_root)"

n=0
fail=0
ok()    { n=$((n+1)); echo "ok $n - $1"; }
nok()   {
  n=$((n+1)); echo "not ok $n - $1"
  if [[ -n "${2:-}" ]]; then
    # YAML-ish diagnostic block per TAP-13.
    printf '  ---\n  diag: |\n'
    printf '    %s\n' "${2//$'\n'/$'\n    '}"
    printf '  ...\n'
  fi
  fail=$((fail+1))
}
skip()  { n=$((n+1)); echo "ok $n - $1 # SKIP ${2:-}"; }

# ---------- tests ------------------------------------------------------------

# T1: non-login non-interactive inherits EDITOR.
test_T1() {
  local desc="zsh -c inherits EDITOR=nvim (non-login, non-interactive)"
  local out
  out="$(zrun -c 'echo $EDITOR' 2>/dev/null)"
  if [[ "$out" == "nvim" ]]; then ok "$desc"; else nok "$desc" "expected 'nvim', got '$out'"; fi
}

# Why this normalization (used by T2 + T3 below):
#
# Both tests probe `echo $EDITOR` from an interactive zsh and compare the
# captured stdout against the literal string "nvim". On warm zinit caches the
# stdout is just "nvim\n" and a trivial compare works. On a *cold* zinit cache
# (CI fresh runners, or any host whose `~/.local/share/zinit` was just wiped)
# zinit's plugin clone + instant-prompt path emits substantial noise on
# stdout *before* the user's `echo` line:
#   * ANSI CSI escapes:  \e[<params><letter>   (color, cursor save/restore,
#                                                cursor hide \e[?25l, etc.)
#   * ANSI OSC escapes:  \e]<params>\a         (terminal title pushes)
#   * Carriage returns:  \r                    (progress-bar overwrites from
#                                                git clone / zinit downloader)
# Because `\r` is *not* `\n`, naive `tail -n1` sees a single physical line
# that ends in `...\rnvim` and returns `\rnvim` — which fails the
# `[[ "$out" == "nvim" ]]` compare. (The TAP diag printer then renders the
# `\r` as a column-zero return, which is why PR #27's CI log showed the
# misleading `expected 'nvim', got '\nnvim'`.)
#
# Fresh CI runners always hit this regime: there is no warm-up to suppress
# the clone progress, so every job sees full cold-cache noise.
#
# The pipeline below normalizes that noise:
#   1. sed strips CSI sequences  (\e[…<letter>)
#   2. sed strips OSC sequences  (\e]…\a)
#   3. sed converts \r → \n      (so embedded CR splits into separate lines)
#   4. awk picks the last NON-EMPTY line (`NF { last = $0 }` — preferable to
#      `tail -n1`, which would return a trailing blank line if any).
# Pure POSIX, works under both GNU sed/awk (Linux) and BSD sed/awk (macOS).

# T2: non-login interactive inherits EDITOR.
test_T2() {
  local desc="zsh -ic inherits EDITOR=nvim (interactive non-login)"
  local out
  out="$(zrun -ic 'echo $EDITOR' 2>/dev/null)"
  out="$(
    printf '%s\n' "$out" \
      | sed -E $'s/\x1b\\[[0-9;?]*[a-zA-Z]//g; s/\x1b\\][^\x07]*\x07//g; s/\r/\\n/g' \
      | awk 'NF { last = $0 } END { print last }'
  )"
  if [[ "$out" == "nvim" ]]; then ok "$desc"; else nok "$desc" "expected 'nvim', got '$out'"; fi
}

# T3: login interactive — baseline.
test_T3() {
  local desc="zsh -lic inherits EDITOR=nvim (login interactive)"
  local out
  out="$(zrun -lic 'echo $EDITOR' 2>/dev/null)"
  out="$(
    printf '%s\n' "$out" \
      | sed -E $'s/\x1b\\[[0-9;?]*[a-zA-Z]//g; s/\x1b\\][^\x07]*\x07//g; s/\r/\\n/g' \
      | awk 'NF { last = $0 } END { print last }'
  )"
  if [[ "$out" == "nvim" ]]; then ok "$desc"; else nok "$desc" "expected 'nvim', got '$out'"; fi
}

# T4: PATH propagation — ~/.local/bin must be on PATH.
test_T4() {
  local desc="zsh -c PATH contains \$HOME/.local/bin"
  local out
  out="$(zrun -c 'echo $PATH' 2>/dev/null)"
  if [[ ":$out:" == *":$HOME/.local/bin:"* ]]; then
    ok "$desc"
  else
    nok "$desc" "PATH=$out"
  fi
}

# T5: bat resolves in non-login (via ~/.local/bin/bat -> batcat on Linux,
# native bat on macOS). Skip if neither installed.
test_T5() {
  local desc="bat (or batcat) is on PATH in non-login zsh"
  if ! command -v bat >/dev/null 2>&1 && ! command -v batcat >/dev/null 2>&1; then
    skip "$desc" "neither bat nor batcat installed on host"
    return
  fi
  local out
  out="$(zrun -c 'command -v bat || command -v batcat' 2>/dev/null)"
  if [[ -n "$out" && -e "$out" ]]; then
    ok "$desc"
  else
    nok "$desc" "command -v returned: '$out'"
  fi
}

# T6: login mesg behavior preserved on Linux. mesg may legitimately exit non-zero
# if not attached to a tty, but the shell should still exit 0 (PR-9 added a
# tty-guard so mesg is skipped in non-tty contexts on Linux).
test_T6() {
  local desc="zsh -lic 'true' exits 0 on Linux (mesg tty-guard works)"
  if [[ "$(uname -s)" != "Linux" ]]; then
    skip "$desc" "not Linux"
    return
  fi
  zrun -lic 'true' </dev/null >/dev/null 2>&1
  local rc=$?
  if [[ $rc -eq 0 ]]; then ok "$desc"; else nok "$desc" "exit=$rc"; fi
}

# T7: mesg failure non-fatal in non-tty even for non-login shells.
test_T7() {
  local desc="non-tty zsh -c reaches end despite any mesg-like noise"
  local out
  out="$(zrun -c 'mesg n 2>/dev/null; echo done' </dev/null 2>/dev/null)"
  if [[ "$out" == *"done"* ]]; then
    ok "$desc"
  else
    nok "$desc" "expected output to contain 'done', got: '$out'"
  fi
}

# T8: alias propagation — alias `v` should expand to $EDITOR.
test_T8() {
  local desc="zsh -ic defines alias v=\$EDITOR"
  local out
  out="$(zrun -ic 'alias v' 2>/dev/null | tail -n1)"
  # zshrc:  alias v='$EDITOR'   →  `alias v` prints  v='$EDITOR'  (single-quoted).
  if [[ "$out" == *"v="*"EDITOR"* ]]; then
    ok "$desc"
  else
    nok "$desc" "alias v output: '$out'"
  fi
}

# T9: PATH ordering — ~/.local/bin must come before /usr/bin.
test_T9() {
  local desc="\$HOME/.local/bin precedes /usr/bin in PATH"
  local pathstr
  pathstr="$(zrun -c 'echo $PATH' 2>/dev/null)"
  # Find earliest index of each in :-split order.
  local local_idx="" usr_idx="" i=0 elem
  IFS=':' read -r -a parts <<<"$pathstr"
  for elem in "${parts[@]}"; do
    if [[ -z "$local_idx" && "$elem" == "$HOME/.local/bin" ]]; then local_idx=$i; fi
    if [[ -z "$usr_idx"   && "$elem" == "/usr/bin"          ]]; then usr_idx=$i;   fi
    i=$((i+1))
  done
  if [[ -z "$local_idx" ]]; then
    nok "$desc" "\$HOME/.local/bin not in PATH: $pathstr"
  elif [[ -z "$usr_idx" ]]; then
    # /usr/bin not present — still a pass for "precedes" since absent ≠ before.
    ok "$desc"
  elif (( local_idx < usr_idx )); then
    ok "$desc"
  else
    nok "$desc" "\$HOME/.local/bin idx=$local_idx, /usr/bin idx=$usr_idx in: $pathstr"
  fi
}

# T10: performance gate — login interactive zsh starts in under 1.5s.
# Generous threshold accounts for zinit + p10k + first-run plugin clones.
test_T10() {
  local desc="zsh -lic 'exit' starts in under 1.5s (warm cache)"
  # Warm-up run to avoid penalising first-run plugin cloning.
  zrun -lic 'exit' >/dev/null 2>&1 || true
  # Measured run.
  local t0 t1 elapsed_ms
  if command -v python3 >/dev/null 2>&1; then
    t0=$(python3 -c 'import time;print(int(time.time()*1000))')
    zrun -lic 'exit' >/dev/null 2>&1
    t1=$(python3 -c 'import time;print(int(time.time()*1000))')
    elapsed_ms=$((t1 - t0))
  else
    # Fallback: $SECONDS resolution is 1s — multiply.
    local s0=$SECONDS
    zrun -lic 'exit' >/dev/null 2>&1
    elapsed_ms=$(( (SECONDS - s0) * 1000 ))
  fi
  if (( elapsed_ms < 1500 )); then
    ok "$desc (${elapsed_ms}ms)"
  else
    nok "$desc" "took ${elapsed_ms}ms (threshold 1500ms)"
  fi
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
test_T9
test_T10

echo "# passed=$((n - fail)) failed=$fail of $n"
exit "$fail"
