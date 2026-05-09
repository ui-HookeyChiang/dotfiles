#!/usr/bin/env bash
# tests/test-install-projects.sh — TAP-13 regression suite for --with-projects.
#
# Verifies the install.sh --with-projects flag plumbing, dry-run output, the
# auto-flip of --with-node, and the seed_env awk rewrite logic. Tests do NOT
# clone real repositories (network-dependent and slow); they only exercise the
# --dry-run command path and the awk seeding pass against a fixture
# .env.example.
#
# Output: TAP-13 (https://testanything.org/tap-version-13-specification.html).
# Exit 0 on all pass, non-zero count of failures otherwise.

set -u  # NOT -e: keep running tests after a failure.

# ---------- locate repo ------------------------------------------------------
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
install_sh="$repo_root/install.sh"

# Sandbox dir.
tmp_dir="$(mktemp -d -t install-projects-test.XXXXXX)"
trap 'rm -rf -- "$tmp_dir"' EXIT

# ---------- TAP helpers ------------------------------------------------------
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

# Dry-run runner — capture stdout+stderr without executing real installer side
# effects. parse_flags returns; dry-run mode short-circuits actual mutations.
# But install.sh runs detect_os, ensure_pkg_manager, etc., on real system.
# To keep tests fast and host-agnostic, we instead invoke install.sh in a way
# that exercises only parse_flags + the --dry-run plan output. We do this by
# letting the script run all the way through (it is idempotent + dry-run by
# design); on macOS/Linux this is acceptable for a flag-plumbing test.
run_dryrun() {
  # First arg: optional env var prefix string like "DOTFILES_PROJECTS_DIR=/tmp/x".
  # Remaining args: install.sh flags.
  local env_prefix="$1"
  shift
  if [[ -n "$env_prefix" ]]; then
    env "$env_prefix" bash "$install_sh" "$@" 2>&1
  else
    bash "$install_sh" "$@" 2>&1
  fi
}

# ---------- tests ------------------------------------------------------------

# T1: bash -n syntax check.
test_T1() {
  local desc="install.sh passes bash -n syntax check"
  local err
  if err="$(bash -n "$install_sh" 2>&1)"; then
    ok "$desc"
  else
    nok "$desc" "$err"
  fi
}

# T2: --help exits 0 and contains --with-projects.
test_T2() {
  local desc="./install.sh --help exits 0 and mentions --with-projects"
  local out rc
  out="$(bash "$install_sh" --help 2>&1)"
  rc=$?
  if (( rc != 0 )); then
    nok "$desc" "exit=$rc"
    return
  fi
  if [[ "$out" != *"--with-projects"* ]]; then
    nok "$desc" "--with-projects not found in --help output"
    return
  fi
  ok "$desc"
}

# T3: --with-projects --dry-run announces auto-enabled --with-node and runs install_node.
test_T3() {
  local desc="--with-projects --dry-run announces auto-enabled --with-node + runs install_node"
  local out
  out="$(run_dryrun "" --with-projects --dry-run)"
  if [[ "$out" == *"auto-enabled --with-node"* ]] && [[ "$out" == *"install_node"* ]]; then
    ok "$desc"
  else
    nok "$desc" "expected both 'auto-enabled --with-node' and 'install_node' in output"
  fi
}

# T4: --with-projects --with-node --dry-run does NOT print auto-enable note (already set).
test_T4() {
  local desc="--with-projects --with-node --dry-run suppresses auto-enable note"
  local out count
  out="$(run_dryrun "" --with-projects --with-node --dry-run)"
  # POSIX-compatible occurrence count of the literal string.
  count="$(printf '%s\n' "$out" | grep -c 'auto-enabled --with-node' || true)"
  if [[ "$count" == "0" ]]; then
    ok "$desc"
  else
    nok "$desc" "expected 0 occurrences, got $count"
  fi
}

# T5: DOTFILES_PROJECTS_DIR override propagates (>=3 references in dry-run plan).
test_T5() {
  local desc="DOTFILES_PROJECTS_DIR override propagates to all 3 project paths"
  local out count
  out="$(run_dryrun "DOTFILES_PROJECTS_DIR=/tmp/proj-test" --with-projects --dry-run)"
  count="$(printf '%s\n' "$out" | grep -c '/tmp/proj-test/' || true)"
  if (( count >= 3 )); then
    ok "$desc (matched $count lines)"
  else
    nok "$desc" "expected >=3 matches, got $count"
  fi
}

# T6: --all turns on install_projects.
test_T6() {
  local desc="--all --dry-run runs install_projects step"
  local out
  out="$(run_dryrun "" --all --dry-run)"
  if [[ "$out" == *"install_projects"* ]]; then
    ok "$desc"
  else
    nok "$desc" "expected 'install_projects' in --all dry-run output"
  fi
}

# T7: bare --dry-run does NOT run install_projects.
test_T7() {
  local desc="bare --dry-run does NOT run install_projects"
  local out count
  out="$(run_dryrun "" --dry-run)"
  count="$(printf '%s\n' "$out" | grep -c 'install_projects' || true)"
  if [[ "$count" == "0" ]]; then
    ok "$desc"
  else
    nok "$desc" "expected 0 occurrences, got $count"
  fi
}

# T8: seed_env awk rewrite — comments, blanks, KEY=value, KEY=val # inline,
# URLs with '=' all behave as designed.
test_T8() {
  local desc="seed_env rewrites all KEY= lines to FIXME-PLEASE-FILL while preserving comments/blanks"

  # Build a fixture .env.example.
  local proj="$tmp_dir/seedtest"
  mkdir -p "$proj"
  cat >"$proj/.env.example" <<'EOF'
# Top-level comment
SHIOAJI_API_KEY=replace_me

# Inline comment after value
TELEGRAM_BOT_TOKEN=12345  # 身分證
DATABASE_URL=sqlite:///foo.db?cache=shared
   # Indented comment

EMPTY_KEY=
EOF

  # Source install.sh in a way that defines seed_env without running main.
  # Approach: extract just the seed_env function via a regex-bounded slice and
  # eval it in the current shell. Cleaner: source the whole script with a
  # guarded main wrapper. install.sh always calls `main "$@"` at file end,
  # so sourcing executes main. We sidestep by running an inline bash subshell
  # that overrides main() before sourcing.
  local out rc
  out="$(
    set +u
    DRY_RUN=0
    note() { :; }
    err()  { :; }
    log()  { :; }
    run()  { "$@"; }

    # Pull only the seed_env definition out of install.sh via awk, then eval.
    awk '/^seed_env\(\) \{$/{flag=1} flag{print} flag && /^\}$/{flag=0; exit}' "$install_sh" > "$tmp_dir/seed_env.bash"
    # shellcheck disable=SC1090
    . "$tmp_dir/seed_env.bash"

    seed_env "$proj/.env" "$proj/.env.example"
  )"
  rc=$?
  if (( rc != 0 )); then
    nok "$desc" "seed_env returned $rc; output: $out"
    return
  fi

  if [[ ! -f "$proj/.env" ]]; then
    nok "$desc" ".env not created"
    return
  fi

  # Verify comment lines preserved verbatim.
  local got_comment
  got_comment="$(grep -c '^# Top-level comment$' "$proj/.env" || true)"
  if [[ "$got_comment" != "1" ]]; then
    nok "$desc" "top-level comment missing/changed in $proj/.env: $(cat "$proj/.env")"
    return
  fi

  # Verify all KEY= lines were rewritten.
  local got_fixme
  got_fixme="$(grep -c 'FIXME-PLEASE-FILL' "$proj/.env" || true)"
  if (( got_fixme < 4 )); then
    nok "$desc" "expected >=4 FIXME-PLEASE-FILL lines, got $got_fixme; file: $(cat "$proj/.env")"
    return
  fi

  # Verify no original values bled through.
  if grep -qE '(replace_me|12345|sqlite:///)' "$proj/.env"; then
    nok "$desc" "original values leaked into .env: $(cat "$proj/.env")"
    return
  fi

  # Verify each rewritten KEY= line has the form KEY=FIXME-PLEASE-FILL with no
  # trailing inline comment (per spec: trailing inline comments are NOT
  # preserved).
  if grep -E '^[A-Za-z_][A-Za-z0-9_]*=FIXME-PLEASE-FILL[[:space:]]+#' "$proj/.env" >/dev/null; then
    nok "$desc" "rewritten line should not have trailing inline comment: $(cat "$proj/.env")"
    return
  fi

  # Idempotency: re-running should leave the existing .env untouched.
  local before after
  before="$(cat "$proj/.env")"
  (
    set +u
    DRY_RUN=0
    note() { :; }
    err()  { :; }
    log()  { :; }
    run()  { "$@"; }
    # shellcheck disable=SC1090
    . "$tmp_dir/seed_env.bash"
    seed_env "$proj/.env" "$proj/.env.example" >/dev/null
  )
  after="$(cat "$proj/.env")"
  if [[ "$before" != "$after" ]]; then
    nok "$desc" "second seed_env run mutated existing .env"
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
