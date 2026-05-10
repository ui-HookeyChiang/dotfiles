#!/usr/bin/env bash
# tests/test-install-secrets.sh — TAP-13 regression suite for --with-secrets.
#
# Verifies the install.sh --with-secrets flag plumbing, dry-run output, the
# auto-flip of --with-projects, and the seed_one_env_tpl per-line matcher.
#
# T6/T7/T9 are macOS-only: they exercise real `security` keychain operations
# with a unique-per-run service prefix (test-env-tpl-$$-...) and trap-cleanup
# on EXIT. On Linux/CI hosts they gate-skip with a PASS line.
#
# Output: TAP-13 (https://testanything.org/tap-version-13-specification.html).
# Exit 0 on all pass, non-zero count of failures otherwise.

set -u  # NOT -e: keep running tests after a failure.

# ---------- locate repo ------------------------------------------------------
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
install_sh="$repo_root/install.sh"

# Sandbox dir.
tmp_dir="$(mktemp -d -t install-secrets-test.XXXXXX)"

# Unique per-run keychain prefix to avoid collisions across parallel runs.
kc_prefix="test-env-tpl-$$"
KC_ENTRIES=()  # services we created, for trap cleanup.

cleanup() {
  rm -rf -- "$tmp_dir" 2>/dev/null || true
  if [[ "$(uname -s)" == "Darwin" ]]; then
    local svc
    for svc in "${KC_ENTRIES[@]:-}"; do
      [[ -n "$svc" ]] || continue
      security delete-generic-password -s "$svc" -a "$USER" >/dev/null 2>&1 || true
    done
  fi
}
trap cleanup EXIT

# ---------- TAP helpers ------------------------------------------------------
plan_count=9
echo "1..$plan_count"
echo "# repo_root=$repo_root"
echo "# kc_prefix=$kc_prefix"

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

run_dryrun() {
  local env_prefix="$1"
  shift
  if [[ -n "$env_prefix" ]]; then
    env "$env_prefix" bash "$install_sh" "$@" 2>&1
  else
    bash "$install_sh" "$@" 2>&1
  fi
}

# Source seed_one_env_tpl out of install.sh into a subshell so we can call it
# directly without running main(). Returns the function body inline-evalled.
extract_seed_one_env_tpl() {
  awk '/^seed_one_env_tpl\(\) \{$/{flag=1} flag{print} flag && /^\}$/{flag=0; exit}' "$install_sh"
}

is_macos() {
  [[ "$(uname -s)" == "Darwin" ]]
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

# T2: --help mentions --with-secrets.
test_T2() {
  local desc="./install.sh --help exits 0 and mentions --with-secrets"
  local out rc
  out="$(bash "$install_sh" --help 2>&1)"
  rc=$?
  if (( rc != 0 )); then
    nok "$desc" "exit=$rc"
    return
  fi
  if [[ "$out" != *"--with-secrets"* ]]; then
    nok "$desc" "--with-secrets not found in --help output"
    return
  fi
  ok "$desc"
}

# T3: --with-secrets --dry-run produces zero ^ERROR lines.
test_T3() {
  local desc="--with-secrets --dry-run produces zero ERROR lines"
  local out count
  out="$(run_dryrun "" --with-secrets --dry-run)"
  count="$(printf '%s\n' "$out" | grep -c '^ERROR' || true)"
  if [[ "$count" == "0" ]]; then
    ok "$desc"
  else
    nok "$desc" "expected 0 ERROR lines, got $count; output: $out"
  fi
}

# T4: --with-secrets auto-enables --with-projects (announcement appears).
test_T4() {
  local desc="--with-secrets auto-enables --with-projects (announcement appears)"
  local out
  out="$(run_dryrun "" --with-secrets --dry-run)"
  if [[ "$out" == *"auto-enabled --with-projects"* ]]; then
    ok "$desc"
  else
    nok "$desc" "expected 'auto-enabled --with-projects' note in output"
  fi
}

# T5: --with-projects --with-secrets (both explicit) — no double-flip note.
test_T5() {
  local desc="--with-projects --with-secrets explicit: no auto-enable --with-projects note"
  local out count
  out="$(run_dryrun "" --with-projects --with-secrets --dry-run)"
  count="$(printf '%s\n' "$out" | grep -c 'auto-enabled --with-projects' || true)"
  if [[ "$count" == "0" ]]; then
    ok "$desc"
  else
    nok "$desc" "expected 0 occurrences, got $count"
  fi
}

# T6: seed_one_env_tpl per-line matcher with 3-line fixture (Darwin-only).
test_T6() {
  local desc="seed_one_env_tpl resolves keychain hit + literal + comment correctly"
  if ! is_macos; then
    ok "$desc (skipped: not macOS)"
    return
  fi

  local svc="${kc_prefix}-foo"
  KC_ENTRIES+=("$svc")
  if ! security add-generic-password -s "$svc" -a "$USER" -w 'resolved-value' 2>/dev/null; then
    # Already exists from a prior run? Update it.
    security delete-generic-password -s "$svc" -a "$USER" >/dev/null 2>&1 || true
    if ! security add-generic-password -s "$svc" -a "$USER" -w 'resolved-value' 2>&1; then
      nok "$desc" "could not seed keychain entry $svc"
      return
    fi
  fi

  local proj="$tmp_dir/t6-proj"
  mkdir -p "$proj"
  cat > "$proj/.env.tpl" <<TPL
# header comment
DATABASE_URL=sqlite:///foo.db
FOO=\$(security find-generic-password -s ${svc} -w)
TPL

  local out rc
  out="$(
    set +u
    OS="macos"
    USER="$USER"
    SEED_SECRETS_MISSING=()
    DRY_RUN=0
    note() { printf '    %s\n' "$*" >&2; }
    err()  { printf 'ERROR: %s\n' "$*" >&2; }
    log()  { printf '==> %s\n' "$*" >&2; }
    # shellcheck disable=SC2034
    REPO_ROOT="$(pwd)"

    eval "$(extract_seed_one_env_tpl)"
    seed_one_env_tpl "t6-proj" "$proj/.env.tpl" "$proj/.env" 2>&1
  )"
  rc=$?

  if (( rc != 0 )); then
    nok "$desc" "rc=$rc; out=$out"
    return
  fi

  if [[ ! -f "$proj/.env" ]]; then
    nok "$desc" ".env not created; out=$out"
    return
  fi

  # Verify content: header preserved, DATABASE_URL literal preserved, FOO resolved.
  local content
  content="$(cat "$proj/.env")"
  if [[ "$content" != *"# header comment"* ]]; then
    nok "$desc" "header comment missing; content=$content"
    return
  fi
  if [[ "$content" != *"DATABASE_URL=sqlite:///foo.db"* ]]; then
    nok "$desc" "DATABASE_URL literal missing; content=$content"
    return
  fi
  if [[ "$content" != *"FOO=resolved-value"* ]]; then
    nok "$desc" "FOO not resolved to 'resolved-value'; content=$content"
    return
  fi

  # Verify chmod 600.
  local mode
  mode="$(stat -f '%Mp%Lp' "$proj/.env" 2>/dev/null || stat -c '%a' "$proj/.env" 2>/dev/null)"
  if [[ "$mode" != "0600" && "$mode" != "600" ]]; then
    nok "$desc" "expected mode 0600/600, got $mode"
    return
  fi

  ok "$desc"
}

# T7: seed_one_env_tpl with missing keychain entry (Darwin-only).
test_T7() {
  local desc="seed_one_env_tpl on missing keychain entry writes KEY= and accumulates miss"
  if ! is_macos; then
    ok "$desc (skipped: not macOS)"
    return
  fi

  local svc="${kc_prefix}-not-there"
  # Ensure it doesn't exist.
  security delete-generic-password -s "$svc" -a "$USER" >/dev/null 2>&1 || true

  local proj="$tmp_dir/t7-proj"
  mkdir -p "$proj"
  cat > "$proj/.env.tpl" <<TPL
MISSING=\$(security find-generic-password -s ${svc} -w)
TPL

  local out rc
  out="$(
    set +u
    OS="macos"
    USER="$USER"
    SEED_SECRETS_MISSING=()
    DRY_RUN=0
    note() { printf '    %s\n' "$*" >&2; }
    err()  { printf 'ERROR: %s\n' "$*" >&2; }
    log()  { printf '==> %s\n' "$*" >&2; }

    eval "$(extract_seed_one_env_tpl)"
    seed_one_env_tpl "t7-proj" "$proj/.env.tpl" "$proj/.env" 2>&1
    # echo missing array contents to stdout so parent can verify.
    printf 'MISSING_COUNT=%d\n' "${#SEED_SECRETS_MISSING[@]}"
    for e in "${SEED_SECRETS_MISSING[@]:-}"; do printf 'MISSING_ENTRY=%s\n' "$e"; done
  )"
  rc=$?

  if (( rc != 0 )); then
    nok "$desc" "rc=$rc; out=$out"
    return
  fi

  if ! grep -q '^MISSING=$' "$proj/.env"; then
    nok "$desc" "expected 'MISSING=' empty; got: $(cat "$proj/.env")"
    return
  fi

  if [[ "$out" != *"MISSING_ENTRY=t7-proj|MISSING|${svc}"* ]]; then
    nok "$desc" "expected SEED_SECRETS_MISSING tuple; got: $out"
    return
  fi

  ok "$desc"
}

# T8: Pre-existing .env survives --with-secrets re-run (S4).
test_T8() {
  local desc="pre-existing .env survives seed_one_env_tpl invocation (S4)"
  local proj="$tmp_dir/t8-proj"
  mkdir -p "$proj"
  cat > "$proj/.env.tpl" <<'TPL'
FOO=$(security find-generic-password -s does-not-matter -w)
TPL
  echo "FOO=hand-edited" > "$proj/.env"
  chmod 600 "$proj/.env"

  # On Linux this still works because seed_one_env_tpl gates on macOS first
  # (returns 0 with a note). To exercise the S4 branch on either OS, source
  # the function and override OS to macos so we hit the .env-exists branch.
  local out rc
  out="$(
    set +u
    OS="macos"
    USER="$USER"
    SEED_SECRETS_MISSING=()
    DRY_RUN=0
    note() { printf '    %s\n' "$*" >&2; }
    err()  { printf 'ERROR: %s\n' "$*" >&2; }
    log()  { printf '==> %s\n' "$*" >&2; }

    eval "$(extract_seed_one_env_tpl)"
    seed_one_env_tpl "t8-proj" "$proj/.env.tpl" "$proj/.env" 2>&1
  )"
  rc=$?

  if (( rc != 0 )); then
    nok "$desc" "rc=$rc; out=$out"
    return
  fi

  if [[ "$(cat "$proj/.env")" != "FOO=hand-edited" ]]; then
    nok "$desc" "pre-existing .env was clobbered: $(cat "$proj/.env")"
    return
  fi

  if [[ "$out" != *"present, leaving as-is"* ]]; then
    nok "$desc" "expected 'leaving as-is' note; got: $out"
    return
  fi

  ok "$desc"
}

# T9: Dry-run does NOT call security (Darwin-only fixture-template check).
test_T9() {
  local desc="dry-run does NOT invoke security; static -s parse lists services"
  if ! is_macos; then
    ok "$desc (skipped: not macOS)"
    return
  fi

  local proj="$tmp_dir/t9-proj"
  mkdir -p "$proj"
  cat > "$proj/.env.tpl" <<TPL
FOO=\$(security find-generic-password -s ${kc_prefix}-svc-a -w)
BAR=\$(security find-generic-password -s ${kc_prefix}-svc-b -w)
BAZ=literal
TPL

  # Override PATH to a minimal set EXCLUDING /usr/bin (which has security)
  # so that any accidental call would fail with command not found.
  # We then capture and verify dry-run output mentions both service names
  # and never contains a "security: ... not found" error.
  local out rc
  out="$(
    set +u
    OS="macos"
    USER="$USER"
    SEED_SECRETS_MISSING=()
    DRY_RUN=1
    note() { printf '    %s\n' "$*" >&2; }
    err()  { printf 'ERROR: %s\n' "$*" >&2; }
    log()  { printf '==> %s\n' "$*" >&2; }

    eval "$(extract_seed_one_env_tpl)"
    PATH=/usr/local/bin:/bin seed_one_env_tpl "t9-proj" "$proj/.env.tpl" "$proj/.env" 2>&1
  )"
  rc=$?

  if (( rc != 0 )); then
    nok "$desc" "rc=$rc; out=$out"
    return
  fi

  if [[ -f "$proj/.env" ]]; then
    nok "$desc" "dry-run created .env (should NOT)"
    return
  fi

  if [[ "$out" != *"${kc_prefix}-svc-a"* ]] || [[ "$out" != *"${kc_prefix}-svc-b"* ]]; then
    nok "$desc" "dry-run did not list both service names; out=$out"
    return
  fi

  if [[ "$out" == *"security:"*"not found"* ]] || [[ "$out" == *"command not found"* ]]; then
    nok "$desc" "dry-run accidentally invoked security; out=$out"
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
test_T9

echo "# passed=$((n - fail)) failed=$fail of $n"
exit "$fail"
