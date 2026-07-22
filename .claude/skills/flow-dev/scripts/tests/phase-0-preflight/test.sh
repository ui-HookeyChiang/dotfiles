#!/bin/bash
# tests/phase-0-preflight/test.sh — behavioral tests for Phase 0 hard gate.
#
# Covers the testable subset of spec §6 scenarios:
#   G1a/G1b/G1d   worktree-detection (non-repo, main checkout, bare repo)
#   G2a/G2b/G2c/G2d/G2e   brainstorming gate ignores disk specs
#   G3 / G3-override / G3b lock mismatch and override
#   G4 / G4-crash         cleanup ordering
#   G5a / G5b-cache-hit / G5b-cache-expired / G5b-fail-not-cached / G5c
#   G6-handoff / G6-autonomous-retry / G6-autonomous-exhaust
#   G7 / G7b              idempotent exclude append
#   G-lint                deliberate mis-tag fails lint
#   G8a / G8b / G8c       G8a done-lock STOP-SAFE under none (no done
#                         concept); G8b corrupt-JSON auto-fix; G8c hard-STOP
#   L1 / L2 / L2-autonomous / L3  lock-validity edge cases
#
# Strategy:
#   For each scenario we materialize a *real* fake repository with
#   `mktemp -d` + `git init` + `git worktree add`, run the script under
#   test against that fake, and assert exit code / stdout JSON shape /
#   stderr prefix. The original repo this script lives in is never
#   touched.
#
# Run: bash flow-dev/scripts/tests/phase-0-preflight/test.sh
#   (or: bash flow-dev/scripts/tests/run-all.sh)

set -uo pipefail

# Suppress Phase 0 Check G (#440) for fixture-based tests. The minimal
# fake-repo .docs-lifecycle.json used here omits the `frontmatter`
# section, which makes `docs-lifecycle lint` raise a KeyError unrelated
# to anything under test. Check G correctness is verified separately
# in #440 with fixture-free reproductions.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$HERE/../.."
PHASE0="$SCRIPTS/phase-0-preflight.sh"
WRITE_LOCK="$SCRIPTS/write-lock.sh"
CLEANUP="$SCRIPTS/post-merge-cleanup.sh"
LINT="$SCRIPTS/lint-stop-prefixes.sh"

FAILED=0
PASSED=0

# ---------------------------------------------------------------------------
# Test helpers

# pass <name>
pass() { echo "  ok   $1"; PASSED=$((PASSED + 1)); }
# fail <name> <details>
fail() {
  echo "  FAIL $1"
  [[ -n "${2:-}" ]] && echo "       $2"
  FAILED=$((FAILED + 1))
}

# assert_eq <name> <expected> <actual>
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"
  else fail "$1" "expected='$2' actual='$3'"
  fi
}
# assert_contains <name> <needle> <haystack>
assert_contains() {
  if [[ "$3" == *"$2"* ]]; then pass "$1"
  else fail "$1" "expected substring '$2' in: $3"
  fi
}
# assert_not_contains <name> <needle> <haystack>
assert_not_contains() {
  if [[ "$3" != *"$2"* ]]; then pass "$1"
  else fail "$1" "unexpected substring '$2' in: $3"
  fi
}

# Make a fake repo + linked worktree, set CWD into the worktree.
# After call: $REPO_ROOT (bare/full repo), $WT (worktree path), CWD=$WT.
make_fake_worktree() {
  REPO_ROOT=$(mktemp -d)
  cd "$REPO_ROOT"
  git init -q -b main .
  git config user.email t@example.com
  git config user.name t
  echo "x" > readme.md && git add . && git commit -q -m init
  git remote add origin "https://example.com/fake.git"
  # Required .docs-lifecycle.json with active/done dirs.
  /bin/cat > .docs-lifecycle.json <<'EOF'
{"version":3,"specs":{"proposed":"docs/specs/proposed/","active":"docs/specs/active/","done":"docs/specs/done/"}}
EOF
  mkdir -p docs/specs/proposed docs/specs/active docs/specs/done docs/superpowers/specs
  git add . && git commit -q -m setup
  WT="$REPO_ROOT/.claude/worktrees/wt1"
  mkdir -p "$REPO_ROOT/.claude/worktrees"
  git worktree add -q -b feat/test "$WT"
  cd "$WT"
  # Also populate config inside the worktree.
  /bin/cat > .docs-lifecycle.json <<'EOF'
{"version":3,"specs":{"proposed":"docs/specs/proposed/","active":"docs/specs/active/","done":"docs/specs/done/"}}
EOF
  mkdir -p docs/specs/proposed docs/specs/active docs/specs/done docs/superpowers/specs
}

# Stub `gh` so `gh auth status` succeeds, no network call.
make_gh_stub_ok() {
  STUB_DIR=$(mktemp -d)
  /bin/cat > "$STUB_DIR/gh" <<'EOF'
#!/bin/bash
if [[ "$1" == "auth" && "$2" == "status" ]]; then exit 0; fi
exit 0
EOF
  chmod +x "$STUB_DIR/gh"
  export PATH="$STUB_DIR:$PATH"
  GH_STUB_DIR="$STUB_DIR"
}
make_gh_stub_fail() {
  STUB_DIR=$(mktemp -d)
  /bin/cat > "$STUB_DIR/gh" <<'EOF'
#!/bin/bash
if [[ "$1" == "auth" && "$2" == "status" ]]; then exit 1; fi
exit 1
EOF
  chmod +x "$STUB_DIR/gh"
  export PATH="$STUB_DIR:$PATH"
  GH_STUB_DIR="$STUB_DIR"
}

# Teardown helper - tracks all created tempdirs.
TEMPS=()
record_temp() { TEMPS+=("$1"); }
cleanup_all() {
  cd /tmp
  for d in "${TEMPS[@]:-}"; do
    if [[ -n "$d" && -d "$d" ]]; then
      # Drop worktrees gracefully.
      find "$d" -name ".git" -type f 2>/dev/null | while read -r gf; do
        wt=$(dirname "$gf")
        git -C "$wt" worktree prune 2>/dev/null || true
      done
      chmod -R u+w "$d" 2>/dev/null || true
      rm -rf "$d"
    fi
  done
}
trap cleanup_all EXIT

# Wrap a test so per-test setup doesn't leak between tests.
new_scenario() {
  echo
  echo "=== $1 ==="
  unset REPO_ROOT WT GH_STUB_DIR STUB_DIR
  # Restore PATH to a sane default before each test.
  export PATH="/usr/local/bin:/usr/bin:/bin"
}

# ---------------------------------------------------------------------------
# G1a — not in a git repo
new_scenario "G1a: not in a git repo"
TMP=$(mktemp -d); record_temp "$TMP"; cd "$TMP"
make_gh_stub_ok
out=$(bash "$PHASE0" "" "$TMP" 2>&1 1>/dev/null); rc=$?
assert_eq "G1a:exit" 1 "$rc"
assert_contains "G1a:STOP-SAFE prefix" "[STOP-SAFE]" "$out"
assert_contains "G1a:EnterWorktree hint" "EnterWorktree" "$out"
assert_contains "G1a:.claude/worktrees path" ".claude/worktrees/" "$out"

# G1b — git repo but not a linked worktree (main checkout)
new_scenario "G1b: main checkout, not a worktree"
REPO=$(mktemp -d); record_temp "$REPO"; cd "$REPO"
git init -q -b main .
git config user.email t@example.com && git config user.name t
echo x > a && git add . && git commit -q -m init
make_gh_stub_ok
out=$(bash "$PHASE0" "" "$REPO" 2>&1 1>/dev/null); rc=$?
assert_eq "G1b:exit" 1 "$rc"
assert_contains "G1b:STOP-SAFE prefix" "[STOP-SAFE]" "$out"
assert_contains "G1b:worktree hint" "worktree" "$out"

# G1d — bare repo (cwd into bare; --git-common-dir == --git-dir).
new_scenario "G1d: bare repo"
BARE=$(mktemp -d); record_temp "$BARE"
git init -q --bare "$BARE"
cd "$BARE"
make_gh_stub_ok
out=$(bash "$PHASE0" "" "$BARE" 2>&1 1>/dev/null); rc=$?
assert_eq "G1d:exit" 1 "$rc"
assert_contains "G1d:STOP-SAFE prefix" "[STOP-SAFE]" "$out"

# ---------------------------------------------------------------------------
# G2a — leftover proposed spec must NOT be auto-resurrected
new_scenario "G2a: leftover docs/specs/proposed/foo.md ignored"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "draft" > docs/specs/proposed/2026-05-14-foo.md
make_gh_stub_ok
stdout=$(bash "$PHASE0" "" "$WT" 2>/dev/null); rc=$?
assert_eq "G2a:exit" 0 "$rc"
assert_contains "G2a:invoke-brainstorming" "invoke-brainstorming" "$stdout"
assert_not_contains "G2a:no foo.md leak" "foo.md" "$stdout"
assert_not_contains "G2a:no proposed/ leak" "docs/specs/proposed/" "$stdout"

# G2b — superpowers/specs ignored
new_scenario "G2b: leftover docs/superpowers/specs/bar.md ignored"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "draft" > docs/superpowers/specs/2026-05-14-bar-design.md
make_gh_stub_ok
stdout=$(bash "$PHASE0" "" "$WT" 2>/dev/null); rc=$?
assert_eq "G2b:exit" 0 "$rc"
assert_contains "G2b:invoke-brainstorming" "invoke-brainstorming" "$stdout"
assert_not_contains "G2b:no bar.md" "bar.md" "$stdout"
assert_not_contains "G2b:no superpowers path" "docs/superpowers/specs/" "$stdout"

# G2c — two proposed files, no "newest wins"
new_scenario "G2c: two proposed/ files, neither auto-picked"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "old" > docs/specs/proposed/2026-04-01-old.md
echo "new" > docs/specs/proposed/2026-05-14-new.md
make_gh_stub_ok
stdout=$(bash "$PHASE0" "" "$WT" 2>/dev/null); rc=$?
assert_eq "G2c:exit" 0 "$rc"
assert_contains "G2c:invoke-brainstorming" "invoke-brainstorming" "$stdout"
assert_not_contains "G2c:no old.md" "old.md" "$stdout"
assert_not_contains "G2c:no new.md" "new.md" "$stdout"

# G2d — proposed/ AND active/ baz.md both exist
new_scenario "G2d: proposed/baz.md + active/baz.md coexist"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "p" > docs/specs/proposed/2026-05-14-baz.md
echo "a" > docs/specs/active/2026-05-14-baz.md
make_gh_stub_ok
stdout=$(bash "$PHASE0" "" "$WT" 2>/dev/null); rc=$?
assert_eq "G2d:exit" 0 "$rc"
assert_contains "G2d:invoke-brainstorming" "invoke-brainstorming" "$stdout"
assert_not_contains "G2d:no baz.md leak" "baz.md" "$stdout"

# G2e — symlink in proposed/ -> active/real.md
new_scenario "G2e: symlink in proposed/ ignored"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "real" > docs/specs/active/2026-05-14-real.md
ln -s "$WT/docs/specs/active/2026-05-14-real.md" docs/specs/proposed/2026-05-14-link.md
make_gh_stub_ok
stdout=$(bash "$PHASE0" "" "$WT" 2>/dev/null); rc=$?
assert_eq "G2e:exit" 0 "$rc"
assert_contains "G2e:invoke-brainstorming" "invoke-brainstorming" "$stdout"
assert_not_contains "G2e:no link.md leak" "link.md" "$stdout"
assert_not_contains "G2e:no real.md leak" "real.md" "$stdout"

# ---------------------------------------------------------------------------
# G3 — lock mismatch must STOP-DANGER, no `rm` suggestion
new_scenario "G3: lock mismatch STOP-DANGER"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "A" > docs/specs/active/2026-05-14-spec-A.md
echo "B" > docs/specs/active/2026-05-14-spec-B.md
make_gh_stub_ok
bash "$WRITE_LOCK" "docs/specs/active/2026-05-14-spec-A.md" "feat/test" "feat/test" >/dev/null
out=$(SD_SPEC_PATH="docs/specs/active/2026-05-14-spec-B.md" bash "$PHASE0" "docs/specs/active/2026-05-14-spec-B.md" "$WT" 2>&1 1>/dev/null); rc=$?
assert_eq "G3:exit" 1 "$rc"
assert_contains "G3:STOP-DANGER prefix" "[STOP-DANGER]" "$out"
assert_contains "G3:both paths in msg (A)" "spec-A.md" "$out"
assert_contains "G3:both paths in msg (B)" "spec-B.md" "$out"
assert_contains "G3:lock mismatch wording" "lock mismatch" "$(echo "$out" | tr '[:upper:]' '[:lower:]')"
assert_contains "G3:SD_FORCE_UNLOCK doc" "SD_FORCE_UNLOCK=1" "$out"
assert_not_contains "G3:no rm suggestion" "rm " "$out"

# G3-override
new_scenario "G3-override: SD_FORCE_UNLOCK=1 unblocks switch"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "A" > docs/specs/active/2026-05-14-spec-A.md
echo "B" > docs/specs/active/2026-05-14-spec-B.md
make_gh_stub_ok
bash "$WRITE_LOCK" "docs/specs/active/2026-05-14-spec-A.md" "feat/test" "feat/test" >/dev/null
stdout=$(SD_FORCE_UNLOCK=1 SD_SPEC_PATH="docs/specs/active/2026-05-14-spec-B.md" bash "$PHASE0" "docs/specs/active/2026-05-14-spec-B.md" "$WT" 2>/dev/null); rc=$?
assert_eq "G3-override:exit" 0 "$rc"
assert_contains "G3-override:skip-brainstorming" "skip-brainstorming" "$stdout"
assert_contains "G3-override:spec-B in stdout" "spec-B.md" "$stdout"

# G3b — same lock, same spec passed: resume happy path
new_scenario "G3b: same lock, same spec = resume"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "A" > docs/specs/active/2026-05-14-spec-A.md
make_gh_stub_ok
bash "$WRITE_LOCK" "docs/specs/active/2026-05-14-spec-A.md" "feat/test" "feat/test" >/dev/null
stdout=$(bash "$PHASE0" "docs/specs/active/2026-05-14-spec-A.md" "$WT" 2>/dev/null); rc=$?
assert_eq "G3b:exit" 0 "$rc"
assert_contains "G3b:skip-brainstorming" "skip-brainstorming" "$stdout"

# ---------------------------------------------------------------------------
# G4 — Phase 5 cleanup ordering
new_scenario "G4: post-merge-cleanup removes lock"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "A" > docs/specs/active/2026-05-14-spec-A.md
make_gh_stub_ok
bash "$WRITE_LOCK" "docs/specs/active/2026-05-14-spec-A.md" "feat/test" "feat/test" >/dev/null
[[ -f "$WT/.flow-dev-lock" ]] && pass "G4:lock written" || fail "G4:lock written"
# Sprint 3 cutover: phase-5-cleanup.sh subsumed by post-merge-cleanup.sh.
# Fixture has no MERGED PR -> SD_FORCE_CLEANUP=1 bypasses the guard;
# SD_SKIP_REMOTE=1 stays out of live gh / git push.
SD_FORCE_CLEANUP=1 SD_SKIP_REMOTE=1 bash "$CLEANUP" single feat/test main >/dev/null 2>&1
[[ ! -f "$WT/.flow-dev-lock" ]] && pass "G4:lock removed" || fail "G4:lock removed"
# spec still under active/ (cleanup does NOT promote)
[[ -f "$WT/docs/specs/active/2026-05-14-spec-A.md" ]] && pass "G4:spec untouched by cleanup" || fail "G4:spec untouched"

# G4-crash — cleanup ran but promote did not. Next preflight must succeed.
new_scenario "G4-crash: lock gone, spec still active/"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "A" > docs/specs/active/2026-05-14-spec-A.md
make_gh_stub_ok
bash "$WRITE_LOCK" "docs/specs/active/2026-05-14-spec-A.md" "feat/test" "feat/test" >/dev/null
SD_FORCE_CLEANUP=1 SD_SKIP_REMOTE=1 bash "$CLEANUP" single feat/test main >/dev/null 2>&1
# After crash-equivalent: lock is gone, spec still active/. Re-invoke Phase 0.
stdout=$(bash "$PHASE0" "" "$WT" 2>/dev/null); rc=$?
assert_eq "G4-crash:exit" 0 "$rc"
assert_contains "G4-crash:invoke-brainstorming" "invoke-brainstorming" "$stdout"

# ---------------------------------------------------------------------------
# G5a — stale SD_SPEC_BACKEND=docs-lifecycle is INERT after the dispatcher
# was removed. With `none` the only backend, there is no backend selection
# and no env validation, so a leftover SD_SPEC_BACKEND from a docs-lifecycle-
# era shell is simply ignored: Phase 0 proceeds exactly as G5a-none.
new_scenario "G5a: stale SD_SPEC_BACKEND=docs-lifecycle ignored, Phase 0 OK"
make_fake_worktree; record_temp "$REPO_ROOT"
rm -f .docs-lifecycle.json
make_gh_stub_ok
stdout=$(SD_SPEC_BACKEND=docs-lifecycle bash "$PHASE0" "" "$WT" 2>/dev/null); rc=$?
assert_eq "G5a:exit" 0 "$rc"
assert_contains "G5a:invoke-brainstorming" "invoke-brainstorming" "$stdout"

# G5a-none — missing .docs-lifecycle.json without env override = backend=none,
# Phase 0 must succeed (uninstall-safe contract).
new_scenario "G5a-none: missing .docs-lifecycle.json = backend=none, Phase 0 OK"
make_fake_worktree; record_temp "$REPO_ROOT"
rm -f .docs-lifecycle.json
make_gh_stub_ok
stdout=$(bash "$PHASE0" "" "$WT" 2>/dev/null); rc=$?
assert_eq "G5a-none:exit" 0 "$rc"
assert_contains "G5a-none:invoke-brainstorming" "invoke-brainstorming" "$stdout"

# G5b — cold cache, gh fails
new_scenario "G5b: gh auth cold-cache fail"
make_fake_worktree; record_temp "$REPO_ROOT"
make_gh_stub_fail
out=$(bash "$PHASE0" "" "$WT" 2>&1 1>/dev/null); rc=$?
assert_eq "G5b:exit" 1 "$rc"
assert_contains "G5b:STOP-SAFE prefix" "[STOP-SAFE]" "$out"
assert_contains "G5b:gh auth login hint" "gh auth login" "$out"

# G5b-cache-hit — pre-warm cache, gh fails, but cache should win
new_scenario "G5b-cache-hit: cache wins over real failure"
make_fake_worktree; record_temp "$REPO_ROOT"
make_gh_stub_fail
GIT_DIR_ABS=$(cd "$WT" && git rev-parse --git-dir)
[[ "$GIT_DIR_ABS" != /* ]] && GIT_DIR_ABS="$WT/$GIT_DIR_ABS"
NOW=$(date +%s)
echo "$NOW ok" > "$GIT_DIR_ABS/.gh-auth-cache"
stdout=$(bash "$PHASE0" "" "$WT" 2>/dev/null); rc=$?
assert_eq "G5b-cache-hit:exit" 0 "$rc"
# Mode is either invoke- or skip- depending; either is fine.
assert_contains "G5b-cache-hit:passed Check B" "brainstorming" "$stdout"

# G5b-cache-expired — stale timestamp
new_scenario "G5b-cache-expired: stale cache forces re-run, then STOPs"
make_fake_worktree; record_temp "$REPO_ROOT"
make_gh_stub_fail
GIT_DIR_ABS=$(cd "$WT" && git rev-parse --git-dir)
[[ "$GIT_DIR_ABS" != /* ]] && GIT_DIR_ABS="$WT/$GIT_DIR_ABS"
STALE=$(( $(date +%s) - 400 ))
echo "$STALE ok" > "$GIT_DIR_ABS/.gh-auth-cache"
out=$(bash "$PHASE0" "" "$WT" 2>&1 1>/dev/null); rc=$?
assert_eq "G5b-cache-expired:exit" 1 "$rc"
assert_contains "G5b-cache-expired:STOP-SAFE" "[STOP-SAFE]" "$out"

# G5b-fail-not-cached — failures must NOT be cached
new_scenario "G5b-fail-not-cached: failures never cached"
make_fake_worktree; record_temp "$REPO_ROOT"
make_gh_stub_fail
GIT_DIR_ABS=$(cd "$WT" && git rev-parse --git-dir)
[[ "$GIT_DIR_ABS" != /* ]] && GIT_DIR_ABS="$WT/$GIT_DIR_ABS"
rm -f "$GIT_DIR_ABS/.gh-auth-cache"
out=$(bash "$PHASE0" "" "$WT" 2>&1 1>/dev/null) || true
if [[ -f "$GIT_DIR_ABS/.gh-auth-cache" ]]; then
  contents=$(/bin/cat "$GIT_DIR_ABS/.gh-auth-cache")
  assert_not_contains "G5b-fail-not-cached:no fail token" "fail" "$contents"
else
  pass "G5b-fail-not-cached: cache file absent (acceptable)"
fi

# G5c — no origin remote
new_scenario "G5c: no origin remote"
make_fake_worktree; record_temp "$REPO_ROOT"
git remote remove origin 2>/dev/null || true
git -C "$REPO_ROOT" remote remove origin 2>/dev/null || true
make_gh_stub_ok
out=$(bash "$PHASE0" "" "$WT" 2>&1 1>/dev/null); rc=$?
assert_eq "G5c:exit" 1 "$rc"
assert_contains "G5c:STOP-SAFE prefix" "[STOP-SAFE]" "$out"
assert_contains "G5c:origin add hint" "git remote add origin" "$out"

# ---------------------------------------------------------------------------
# G6-handoff — flock released on process death; next invocation must succeed.
new_scenario "G6-handoff: flock release across processes"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "A" > docs/specs/active/2026-05-14-spec-A.md
make_gh_stub_ok
# First call writes a lock; second call resumes the same spec.
bash "$WRITE_LOCK" "docs/specs/active/2026-05-14-spec-A.md" "feat/test" "feat/test" >/dev/null
bash "$WRITE_LOCK" "docs/specs/active/2026-05-14-spec-A.md" "feat/test" "feat/test" >/dev/null
# Exactly one lock file on disk after both calls.
[[ -f "$WT/.flow-dev-lock" ]] && pass "G6-handoff:one lock present" || fail "G6-handoff:one lock present"
# Validate exclude has exactly one entry.
GIT_DIR_ABS=$(cd "$WT" && git rev-parse --git-dir)
[[ "$GIT_DIR_ABS" != /* ]] && GIT_DIR_ABS="$WT/$GIT_DIR_ABS"
COUNT=$(grep -c '^/\.flow-dev-lock$' "$GIT_DIR_ABS/info/exclude" || true)
assert_eq "G6-handoff:exclude count" 1 "$COUNT"

# G6-autonomous-exhaust — hold flock externally, --autonomous gives up at 75
new_scenario "G6-autonomous-exhaust: 5 retries exhausted, exit 75"
make_fake_worktree; record_temp "$REPO_ROOT"
make_gh_stub_ok
GIT_DIR_ABS=$(cd "$WT" && git rev-parse --git-dir)
[[ "$GIT_DIR_ABS" != /* ]] && GIT_DIR_ABS="$WT/$GIT_DIR_ABS"
mkdir -p "$GIT_DIR_ABS"
: >>"$GIT_DIR_ABS/flow-dev.flock"
# External holder for 30 seconds (we won't wait full retry budget, just observe behavior).
flock -x "$GIT_DIR_ABS/flow-dev.flock" -c "sleep 30" &
HOLDER=$!
sleep 0.2
out=$(bash "$PHASE0" "" "$WT" --autonomous 2>&1 1>/dev/null); rc=$?
kill "$HOLDER" 2>/dev/null || true
wait "$HOLDER" 2>/dev/null || true
assert_eq "G6-autonomous-exhaust:exit" 75 "$rc"
assert_contains "G6-autonomous-exhaust:STOP-RETRY" "[STOP-RETRY]" "$out"

# G6-interactive-busy — single-attempt failure also yields STOP-RETRY / 75
new_scenario "G6-interactive: flock busy = STOP-RETRY"
make_fake_worktree; record_temp "$REPO_ROOT"
make_gh_stub_ok
GIT_DIR_ABS=$(cd "$WT" && git rev-parse --git-dir)
[[ "$GIT_DIR_ABS" != /* ]] && GIT_DIR_ABS="$WT/$GIT_DIR_ABS"
mkdir -p "$GIT_DIR_ABS"
: >>"$GIT_DIR_ABS/flow-dev.flock"
flock -x "$GIT_DIR_ABS/flow-dev.flock" -c "sleep 5" &
HOLDER=$!
sleep 0.2
out=$(bash "$PHASE0" "" "$WT" 2>&1 1>/dev/null); rc=$?
kill "$HOLDER" 2>/dev/null || true
wait "$HOLDER" 2>/dev/null || true
assert_eq "G6-interactive-busy:exit" 75 "$rc"
assert_contains "G6-interactive-busy:STOP-RETRY" "[STOP-RETRY]" "$out"

# ---------------------------------------------------------------------------
# G7 — idempotent exclude append
new_scenario "G7: write-lock twice → one exclude line"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "A" > docs/specs/active/2026-05-14-spec-A.md
make_gh_stub_ok
bash "$WRITE_LOCK" "docs/specs/active/2026-05-14-spec-A.md" "feat/test" "feat/test" >/dev/null
bash "$WRITE_LOCK" "docs/specs/active/2026-05-14-spec-A.md" "feat/test" "feat/test" >/dev/null
GIT_DIR_ABS=$(cd "$WT" && git rev-parse --git-dir)
[[ "$GIT_DIR_ABS" != /* ]] && GIT_DIR_ABS="$WT/$GIT_DIR_ABS"
COUNT=$(grep -c '^/\.flow-dev-lock$' "$GIT_DIR_ABS/info/exclude" || true)
assert_eq "G7:exclude count" 1 "$COUNT"

# G7b — pre-existing /.flow-dev-lock in exclude → no duplicate
new_scenario "G7b: pre-existing exclude line not duplicated"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "A" > docs/specs/active/2026-05-14-spec-A.md
make_gh_stub_ok
GIT_DIR_ABS=$(cd "$WT" && git rev-parse --git-dir)
[[ "$GIT_DIR_ABS" != /* ]] && GIT_DIR_ABS="$WT/$GIT_DIR_ABS"
mkdir -p "$GIT_DIR_ABS/info"
echo "/.flow-dev-lock" > "$GIT_DIR_ABS/info/exclude"
bash "$WRITE_LOCK" "docs/specs/active/2026-05-14-spec-A.md" "feat/test" "feat/test" >/dev/null
COUNT=$(grep -c '^/\.flow-dev-lock$' "$GIT_DIR_ABS/info/exclude" || true)
assert_eq "G7b:exclude count" 1 "$COUNT"

# ---------------------------------------------------------------------------
# G-lint — deliberate mis-tag must fail the lint
new_scenario "G-lint: mis-tagged STOP fails lint"
TMP=$(mktemp -d); record_temp "$TMP"
/bin/cat > "$TMP/bad.sh" <<'EOF'
#!/bin/bash
echo '[STOP-SAFE] Lock mismatch on spec A vs B.' >&2
echo '            Override: SD_FORCE_UNLOCK=1' >&2
exit 1
EOF
out=$(bash "$LINT" "$TMP/bad.sh" 2>&1); rc=$?
[[ $rc -ne 0 ]] && pass "G-lint:non-zero exit" || fail "G-lint:non-zero exit" "rc=$rc out=$out"
assert_contains "G-lint:reports file" "$TMP/bad.sh" "$out"
assert_contains "G-lint:reports rule" "violation" "$out"

# G-lint-clean — the real Phase 0 scripts should lint clean
new_scenario "G-lint-clean: real Phase 0 scripts pass lint"
out=$(bash "$LINT" 2>&1); rc=$?
assert_eq "G-lint-clean:exit" 0 "$rc"
assert_contains "G-lint-clean:PASS" "PASS" "$out"

# G-lint-helper-mutation — REGRESSION TEST FOR BUG #1.
# The previous lint was blind to helper indirection: flipping the
# stop_danger helper to emit [STOP-SAFE] silently downgraded every
# Tier 2 condition. The new lint must catch this via call-site Tier
# mismatch.
new_scenario "G-lint-helper-mutation: flipped stop_danger helper caught"
TMP=$(mktemp -d); record_temp "$TMP"
cp "$SCRIPTS/phase-0-preflight.sh" "$TMP/mutated.sh"
# Mutate ONLY the stop_danger helper's emitted prefix.
sed -i 's|echo "\[STOP-DANGER\] \$1" >&2|echo "[STOP-SAFE] $1" >\&2|' "$TMP/mutated.sh"
# Sanity-check the mutation landed.
if grep -q 'echo "\[STOP-SAFE\] \$1"' "$TMP/mutated.sh"; then
  pass "G-lint-helper-mutation:sed applied"
else
  fail "G-lint-helper-mutation:sed applied" "mutation did not take effect"
fi
out=$(bash "$LINT" "$TMP/mutated.sh" 2>&1); rc=$?
[[ $rc -ne 0 ]] && pass "G-lint-helper-mutation:non-zero exit" \
  || fail "G-lint-helper-mutation:non-zero exit" "rc=$rc out=$out"
# The detected violation should mention either the helper line or a
# call-site Tier mismatch.
if echo "$out" | grep -Eq 'Tier mismatch|stop_danger'; then
  pass "G-lint-helper-mutation:reports tier mismatch"
else
  fail "G-lint-helper-mutation:reports tier mismatch" "out=$out"
fi

# ---------------------------------------------------------------------------
# G8a — autonomous + lock with spec under done/ → STOP-SAFE under none.
# Under backend=none there is NO done concept (spec item 9): the healthy
# active location is docs/superpowers/specs/, and the done-cleanup arm is
# gated off. A lock pointing under docs/specs/done/ matches neither healthy
# prefix, so Check C STOP-SAFEs it as a generic stale lock — even under
# --autonomous (the success-path auto-clean was a docs-lifecycle behavior:
# "done" meant "promoted, safe to clean"; that meaning is gone). The
# operator must investigate + rm the lock. (T2 red-replay + code-review
# confirmed this is the spec-sanctioned correct behavior, not a bug. It
# would FAIL against the old auto-cleaned-done-promoted path.)
new_scenario "G8a: --autonomous + lock under done/ → STOP-SAFE (no done concept under none)"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "A" > docs/specs/done/2026-05-14-spec-A.md
make_gh_stub_ok
# Hand-craft a lock pointing into done/.
/bin/cat > "$WT/.flow-dev-lock" <<EOF
{"version":1,"spec_path":"docs/specs/done/2026-05-14-spec-A.md","feature_branch":"feat/x","created_at":"2026-01-01T00:00:00Z","skill_version":"flow-dev@deadbeef"}
EOF
out=$(bash "$PHASE0" "" "$WT" --autonomous 2>&1 1>/dev/null); rc=$?
assert_eq "G8a:exit" 1 "$rc"
assert_contains "G8a:STOP-SAFE prefix" "[STOP-SAFE]" "$out"
assert_contains "G8a:stale-lock wording" "Stale lock" "$out"
assert_contains "G8a:names the none active dir" "docs/superpowers/specs/" "$out"
# Lock left in place for the operator to inspect (NOT auto-cleaned under none).
[[ -f "$WT/.flow-dev-lock" ]] && pass "G8a:lock left for operator" || fail "G8a:lock left for operator"
# Negative: must NOT have logged the (deleted) done-promoted auto-clean.
GIT_DIR_ABS=$(cd "$WT" && git rev-parse --git-dir)
[[ "$GIT_DIR_ABS" != /* ]] && GIT_DIR_ABS="$WT/$GIT_DIR_ABS"
if [[ -f "$GIT_DIR_ABS/flow-dev.log" ]] && grep -q "auto-cleaned-done-promoted" "$GIT_DIR_ABS/flow-dev.log"; then
  fail "G8a:no done-promoted auto-clean" "stale auto-cleaned-done-promoted audit entry present"
else
  pass "G8a:no done-promoted auto-clean audit entry"
fi

# G8b — autonomous + corrupt JSON
new_scenario "G8b: --autonomous + corrupt JSON auto-cleanup"
make_fake_worktree; record_temp "$REPO_ROOT"
make_gh_stub_ok
echo "this is { not valid json" > "$WT/.flow-dev-lock"
stdout=$(bash "$PHASE0" "" "$WT" --autonomous 2>/dev/null); rc=$?
assert_eq "G8b:exit" 0 "$rc"
assert_contains "G8b:stale-cleaned" "stale-cleaned" "$stdout"
GIT_DIR_ABS=$(cd "$WT" && git rev-parse --git-dir)
[[ "$GIT_DIR_ABS" != /* ]] && GIT_DIR_ABS="$WT/$GIT_DIR_ABS"
grep -q "auto-cleaned-corrupt-json" "$GIT_DIR_ABS/flow-dev.log" && pass "G8b:audit content" || fail "G8b:audit content"

# G8c — autonomous + Tier 2 mismatch must still STOP-DANGER
new_scenario "G8c: --autonomous + Tier 2 mismatch still STOPs"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "A" > docs/specs/active/2026-05-14-spec-A.md
echo "B" > docs/specs/active/2026-05-14-spec-B.md
make_gh_stub_ok
bash "$WRITE_LOCK" "docs/specs/active/2026-05-14-spec-A.md" "feat/test" "feat/test" >/dev/null
out=$(bash "$PHASE0" "docs/specs/active/2026-05-14-spec-B.md" "$WT" --autonomous 2>&1 1>/dev/null); rc=$?
[[ $rc -ne 0 ]] && pass "G8c:non-zero exit" || fail "G8c:non-zero exit"
assert_contains "G8c:STOP-DANGER" "[STOP-DANGER]" "$out"
[[ -f "$WT/.flow-dev-lock" ]] && pass "G8c:lock untouched" || fail "G8c:lock untouched"

# ---------------------------------------------------------------------------
# L1 — unknown lock schema version
new_scenario "L1: unknown lock schema version"
make_fake_worktree; record_temp "$REPO_ROOT"
make_gh_stub_ok
echo '{"version":99,"spec_path":"x","feature_branch":"y","created_at":"z","skill_version":"w"}' > "$WT/.flow-dev-lock"
out=$(bash "$PHASE0" "" "$WT" 2>&1 1>/dev/null); rc=$?
assert_eq "L1:exit" 1 "$rc"
assert_contains "L1:STOP-SAFE" "[STOP-SAFE]" "$out"
assert_contains "L1:names lock" ".flow-dev-lock" "$out"
assert_contains "L1:unknown wording" "Unknown" "$out"

# L2 — non-existent spec, default mode → STOP
new_scenario "L2: spec_path missing on disk (default mode)"
make_fake_worktree; record_temp "$REPO_ROOT"
make_gh_stub_ok
echo '{"version":1,"spec_path":"docs/specs/active/ghost.md","feature_branch":"y","created_at":"z","skill_version":"w"}' > "$WT/.flow-dev-lock"
out=$(bash "$PHASE0" "" "$WT" 2>&1 1>/dev/null); rc=$?
assert_eq "L2:exit" 1 "$rc"
assert_contains "L2:STOP-SAFE" "[STOP-SAFE]" "$out"
assert_contains "L2:Stale lock wording" "Stale lock" "$out"

# L2-autonomous — same but with --autonomous: auto-cleanup
new_scenario "L2-autonomous: spec missing + --autonomous = auto-fix"
make_fake_worktree; record_temp "$REPO_ROOT"
make_gh_stub_ok
echo '{"version":1,"spec_path":"docs/specs/active/ghost.md","feature_branch":"y","created_at":"z","skill_version":"w"}' > "$WT/.flow-dev-lock"
stdout=$(bash "$PHASE0" "" "$WT" --autonomous 2>/dev/null); rc=$?
assert_eq "L2-autonomous:exit" 0 "$rc"
assert_contains "L2-autonomous:stale-cleaned" "stale-cleaned" "$stdout"
GIT_DIR_ABS=$(cd "$WT" && git rev-parse --git-dir)
[[ "$GIT_DIR_ABS" != /* ]] && GIT_DIR_ABS="$WT/$GIT_DIR_ABS"
grep -q "auto-cleaned-missing-spec" "$GIT_DIR_ABS/flow-dev.log" && pass "L2-autonomous:audit" || fail "L2-autonomous:audit"

# L3 — corrupt JSON in default mode (NOT --autonomous) per M1 = success-path cleanup
new_scenario "L3: corrupt JSON in default mode = auto-cleanup, NOT a STOP"
make_fake_worktree; record_temp "$REPO_ROOT"
make_gh_stub_ok
echo "{ this is not json" > "$WT/.flow-dev-lock"
stdout=$(bash "$PHASE0" "" "$WT" 2>/dev/null); rc=$?
assert_eq "L3:exit" 0 "$rc"
assert_contains "L3:stale-cleaned" "stale-cleaned" "$stdout"
[[ ! -f "$WT/.flow-dev-lock" ]] && pass "L3:lock unlinked" || fail "L3:lock unlinked"

# ---------------------------------------------------------------------------
# L4 — backend=none lock: spec_path under docs/superpowers/specs/ + no
# config must NOT STOP-SAFE on resume. Under backend=none a healthy spec
# lives at docs/superpowers/specs/, which matches NEITHER the active/ nor
# done/ arm of Check C; without the none gate the catch-all `*) stop_safe`
# fires on EVERY locked resume (no escape hatch).
new_scenario "L4: none-backend lock under docs/superpowers/specs/ resumes clean"
make_fake_worktree; record_temp "$REPO_ROOT"
rm -f .docs-lifecycle.json
make_gh_stub_ok
echo "draft" > docs/superpowers/specs/2026-06-05-none-spec-design.md
echo '{"version":2,"spec_path":"docs/superpowers/specs/2026-06-05-none-spec-design.md","feature_branch":"feat/test","created_at":"z","skill_version":"w"}' > "$WT/.flow-dev-lock"
out=$(bash "$PHASE0" "" "$WT" 2>&1 1>/dev/null); rc=$?
stdout=$(bash "$PHASE0" "" "$WT" 2>/dev/null)
assert_eq "L4:exit" 0 "$rc"
assert_not_contains "L4:no STOP-SAFE" "[STOP-SAFE]" "$out"
assert_contains "L4:resume skip-brainstorming" "skip-brainstorming" "$stdout"
assert_contains "L4:resume names the spec" "docs/superpowers/specs/2026-06-05-none-spec-design.md" "$stdout"

# L4-legacy — a PRE-EXISTING docs-lifecycle-era lock whose spec_path is
# under docs/specs/active/, now with NO config (post-removal). Decision:
# treat as HEALTHY (do not break an in-flight migration lock). Under
# backend=none Check C accepts docs/specs/active/ (the default
# LIFECYCLE_ACTIVE) as well as docs/superpowers/specs/.
new_scenario "L4-legacy: pre-existing docs/specs/active/ lock + no config = healthy resume"
make_fake_worktree; record_temp "$REPO_ROOT"
rm -f .docs-lifecycle.json
make_gh_stub_ok
echo "legacy" > docs/specs/active/2026-05-14-legacy-spec.md
echo '{"version":2,"spec_path":"docs/specs/active/2026-05-14-legacy-spec.md","feature_branch":"feat/test","created_at":"z","skill_version":"w"}' > "$WT/.flow-dev-lock"
out=$(bash "$PHASE0" "" "$WT" 2>&1 1>/dev/null); rc=$?
stdout=$(bash "$PHASE0" "" "$WT" 2>/dev/null)
assert_eq "L4-legacy:exit" 0 "$rc"
assert_not_contains "L4-legacy:no STOP-SAFE" "[STOP-SAFE]" "$out"
assert_contains "L4-legacy:resume skip-brainstorming" "skip-brainstorming" "$stdout"

# ---------------------------------------------------------------------------
# PR 2a — Check E (branch consistency) scenarios.
# Spec: docs/specs/active/2026-05-14-phase-0-branch-consistency.md
# ---------------------------------------------------------------------------

# E-G1a — happy path: lock branch == current branch, Check E passes silently.
new_scenario "E-G1a: branch matches lock → Check E PASS silent"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "A" > docs/specs/active/2026-05-14-spec-A.md
make_gh_stub_ok
bash "$WRITE_LOCK" "docs/specs/active/2026-05-14-spec-A.md" "feat/test" "feat/test" >/dev/null
stdout=$(bash "$PHASE0" "" "$WT" 2>/dev/null); rc=$?
assert_eq "E-G1a:exit" 0 "$rc"
assert_contains "E-G1a:skip-brainstorming mode" "skip-brainstorming" "$stdout"
assert_contains "E-G1a:current_branch_at_phase_0 field" "current_branch_at_phase_0" "$stdout"
assert_contains "E-G1a:branch value in JSON" "feat/test" "$stdout"

# E-G1b — branch mismatch → STOP-DANGER with SD_FORCE_BRANCH=1 first.
new_scenario "E-G1b: branch mismatch STOP-DANGER, override hint first"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "A" > docs/specs/active/2026-05-14-spec-A.md
make_gh_stub_ok
bash "$WRITE_LOCK" "docs/specs/active/2026-05-14-spec-A.md" "feat/test" "feat/test" >/dev/null
git -C "$WT" switch -q -c feat/sibling 2>/dev/null || git -C "$WT" checkout -q -b feat/sibling
out=$(bash "$PHASE0" "" "$WT" 2>&1 1>/dev/null); rc=$?
assert_eq "E-G1b:exit" 1 "$rc"
assert_contains "E-G1b:STOP-DANGER prefix" "[STOP-DANGER]" "$out"
assert_contains "E-G1b:Branch mismatch wording" "Branch mismatch" "$out"
assert_contains "E-G1b:current branch in msg" "feat/sibling" "$out"
assert_contains "E-G1b:expected branch in msg" "feat/test" "$out"
assert_contains "E-G1b:SD_FORCE_BRANCH hint" "SD_FORCE_BRANCH=1" "$out"
# K1: env-var hint must appear on the FIRST stderr line (before remediation).
first_line=$(printf '%s\n' "$out" | head -1)
assert_contains "E-G1b:override hint on first line" "SD_FORCE_BRANCH=1" "$first_line"
assert_not_contains "E-G1b:no rm suggestion" "rm " "$out"

# E-G1c — SD_FORCE_BRANCH=1 bypasses Check E with WARN line.
new_scenario "E-G1c: SD_FORCE_BRANCH=1 bypass works"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "A" > docs/specs/active/2026-05-14-spec-A.md
make_gh_stub_ok
bash "$WRITE_LOCK" "docs/specs/active/2026-05-14-spec-A.md" "feat/test" "feat/test" >/dev/null
git -C "$WT" switch -q -c feat/sibling 2>/dev/null || git -C "$WT" checkout -q -b feat/sibling
combined=$(SD_FORCE_BRANCH=1 bash "$PHASE0" "" "$WT" 2>&1); rc=$?
assert_eq "E-G1c:exit" 0 "$rc"
assert_contains "E-G1c:WARN line" "[WARN] SD_FORCE_BRANCH=1" "$combined"
# Re-read stdout-only to confirm JSON mode.
stdout=$(SD_FORCE_BRANCH=1 bash "$PHASE0" "" "$WT" 2>/dev/null); rc=$?
assert_eq "E-G1c:exit-stdout-pass" 0 "$rc"
assert_contains "E-G1c:skip-brainstorming" "skip-brainstorming" "$stdout"
# Lock file is unchanged on disk (single-shot override, no schema mutation).
assert_contains "E-G1c:lock still has feat/test" '"feature_branch":"feat/test"' "$(/bin/cat "$WT/.flow-dev-lock")"

# E-G1c-autonomous — force-branch under --autonomous writes audit line.
new_scenario "E-G1c-autonomous: force-branch + --autonomous → audit log"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "A" > docs/specs/active/2026-05-14-spec-A.md
make_gh_stub_ok
bash "$WRITE_LOCK" "docs/specs/active/2026-05-14-spec-A.md" "feat/test" "feat/test" >/dev/null
git -C "$WT" switch -q -c feat/sibling 2>/dev/null || git -C "$WT" checkout -q -b feat/sibling
stdout=$(SD_FORCE_BRANCH=1 bash "$PHASE0" "" "$WT" --autonomous 2>/dev/null); rc=$?
assert_eq "E-G1c-auto:exit" 0 "$rc"
GIT_DIR_ABS=$(cd "$WT" && git rev-parse --git-dir)
[[ "$GIT_DIR_ABS" != /* ]] && GIT_DIR_ABS="$WT/$GIT_DIR_ABS"
[[ -f "$GIT_DIR_ABS/flow-dev.log" ]] && pass "E-G1c-auto:audit log written" || fail "E-G1c-auto:audit log written"
grep -q "force-branch" "$GIT_DIR_ABS/flow-dev.log" && pass "E-G1c-auto:audit content" || fail "E-G1c-auto:audit content"

# E-G2 — rebase that completed cleanly leaves branch name intact → PASS.
new_scenario "E-G2: clean rebase preserves branch name → PASS"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "A" > docs/specs/active/2026-05-14-spec-A.md
git -C "$WT" add docs/specs/active/2026-05-14-spec-A.md
git -C "$WT" commit -q -m "add A"
make_gh_stub_ok
bash "$WRITE_LOCK" "docs/specs/active/2026-05-14-spec-A.md" "feat/test" "feat/test" >/dev/null
# Trigger a no-op rebase against itself (HEAD) — branch name stays feat/test.
git -C "$WT" rebase -q HEAD >/dev/null 2>&1 || true
stdout=$(bash "$PHASE0" "" "$WT" 2>/dev/null); rc=$?
assert_eq "E-G2:exit" 0 "$rc"
assert_contains "E-G2:skip-brainstorming" "skip-brainstorming" "$stdout"

# E-G3a — detached HEAD via checkout <SHA> → STOP-DANGER, no override.
new_scenario "E-G3a: detached HEAD STOP-DANGER, no override"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "A" > docs/specs/active/2026-05-14-spec-A.md
git -C "$WT" add docs/specs/active/2026-05-14-spec-A.md
git -C "$WT" commit -q -m "add A"
make_gh_stub_ok
bash "$WRITE_LOCK" "docs/specs/active/2026-05-14-spec-A.md" "feat/test" "feat/test" >/dev/null
SHA=$(git -C "$WT" rev-parse HEAD)
git -C "$WT" checkout -q --detach "$SHA"
out=$(bash "$PHASE0" "" "$WT" 2>&1 1>/dev/null); rc=$?
assert_eq "E-G3a:exit" 1 "$rc"
assert_contains "E-G3a:STOP-DANGER" "[STOP-DANGER]" "$out"
assert_contains "E-G3a:Detached HEAD wording" "Detached HEAD inside locked worktree" "$out"
assert_not_contains "E-G3a:no SD_FORCE_BRANCH in first line" "SD_FORCE_BRANCH=1" "$(printf '%s\n' "$out" | head -1)"
assert_not_contains "E-G3a:no rm suggestion" "rm " "$out"

# E-G3c — SD_FORCE_BRANCH=1 does NOT bypass detached HEAD (non-overridable).
new_scenario "E-G3c: SD_FORCE_BRANCH=1 does NOT bypass detached HEAD"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "A" > docs/specs/active/2026-05-14-spec-A.md
git -C "$WT" add docs/specs/active/2026-05-14-spec-A.md
git -C "$WT" commit -q -m "add A"
make_gh_stub_ok
bash "$WRITE_LOCK" "docs/specs/active/2026-05-14-spec-A.md" "feat/test" "feat/test" >/dev/null
SHA=$(git -C "$WT" rev-parse HEAD)
git -C "$WT" checkout -q --detach "$SHA"
out=$(SD_FORCE_BRANCH=1 bash "$PHASE0" "" "$WT" 2>&1 1>/dev/null); rc=$?
assert_eq "E-G3c:exit" 1 "$rc"
assert_contains "E-G3c:STOP-DANGER" "[STOP-DANGER]" "$out"
assert_contains "E-G3c:Detached HEAD wording" "Detached HEAD" "$out"

# E-G4 — no lock at all → Check E does NOT fire, no current_branch field in JSON.
new_scenario "E-G4: no lock → Check E skipped"
make_fake_worktree; record_temp "$REPO_ROOT"
make_gh_stub_ok
git -C "$WT" switch -q -c feat/anything 2>/dev/null || git -C "$WT" checkout -q -b feat/anything
stdout=$(bash "$PHASE0" "" "$WT" 2>/dev/null); rc=$?
assert_eq "E-G4:exit" 0 "$rc"
assert_not_contains "E-G4:no current_branch_at_phase_0 field" "current_branch_at_phase_0" "$stdout"

# E-G5 — pre-PR-1-era lock without feature_branch → pass-through, optional audit.
new_scenario "E-G5: lock without feature_branch passes through"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "A" > docs/specs/active/2026-05-14-spec-A.md
make_gh_stub_ok
# Hand-craft a lock with empty feature_branch.
/bin/cat > "$WT/.flow-dev-lock" <<EOF
{"version":1,"spec_path":"docs/specs/active/2026-05-14-spec-A.md","feature_branch":"","created_at":"2026-01-01T00:00:00Z","skill_version":"flow-dev@deadbeef"}
EOF
stdout=$(bash "$PHASE0" "" "$WT" --autonomous 2>/dev/null); rc=$?
assert_eq "E-G5:exit" 0 "$rc"
GIT_DIR_ABS=$(cd "$WT" && git rev-parse --git-dir)
[[ "$GIT_DIR_ABS" != /* ]] && GIT_DIR_ABS="$WT/$GIT_DIR_ABS"
[[ -f "$GIT_DIR_ABS/flow-dev.log" ]] && \
  grep -q "lock-missing-feature-branch" "$GIT_DIR_ABS/flow-dev.log" && \
  pass "E-G5:audit content" || fail "E-G5:audit content"

# E-G-toctou-missing-field — write-lock.sh refuses when phase_0_branch arg missing.
new_scenario "E-G-toctou-missing-field: write-lock without arg 3 → STOP-DANGER"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "A" > docs/specs/active/2026-05-14-spec-A.md
make_gh_stub_ok
out=$(bash "$WRITE_LOCK" "docs/specs/active/2026-05-14-spec-A.md" "feat/test" 2>&1 1>/dev/null); rc=$?
assert_eq "E-G-toctou-missing:exit" 1 "$rc"
assert_contains "E-G-toctou-missing:STOP-DANGER" "[STOP-DANGER]" "$out"
assert_contains "E-G-toctou-missing:exact wording" "current_branch_at_phase_0 missing from Phase 0 JSON output" "$out"
assert_contains "E-G-toctou-missing:corruption hint" "Possible JSON corruption or incompatible wrapper" "$out"

# E-G-toctou-drift — write-lock detects branch drift from Phase 0 capture.
new_scenario "E-G-toctou-drift: phase_0_branch != current branch → STOP-DANGER"
make_fake_worktree; record_temp "$REPO_ROOT"
echo "A" > docs/specs/active/2026-05-14-spec-A.md
make_gh_stub_ok
# Simulate the TOCTOU race: Phase 0 captured feat/test, but a parallel
# shell switched the worktree to feat/sibling before write-lock's flock.
git -C "$WT" switch -q -c feat/sibling 2>/dev/null || git -C "$WT" checkout -q -b feat/sibling
out=$(bash "$WRITE_LOCK" "docs/specs/active/2026-05-14-spec-A.md" "feat/test" "feat/test" 2>&1 1>/dev/null); rc=$?
assert_eq "E-G-toctou-drift:exit" 1 "$rc"
assert_contains "E-G-toctou-drift:STOP-DANGER" "[STOP-DANGER]" "$out"
assert_contains "E-G-toctou-drift:Branch drift wording" "Branch drift between Phase 0 and write-lock" "$out"
assert_contains "E-G-toctou-drift:was-now in message" "was 'feat/test'" "$out"
assert_contains "E-G-toctou-drift:now in message" "now 'feat/sibling'" "$out"
assert_contains "E-G-toctou-drift:SD_FORCE_BRANCH hint" "SD_FORCE_BRANCH=1" "$(printf '%s\n' "$out" | head -1)"

# E-G-lint-branch-mismatch — flip stop_danger → stop_safe on Branch mismatch site.
# Define BOTH helpers inline so the lint resolves the call-site fn to a real
# emitted prefix, triggering Rule (a) Tier mismatch (not "helper not defined").
new_scenario "E-G-lint-1: branch-mismatch site mistagged → lint fails"
TMP=$(mktemp -d); record_temp "$TMP"
/bin/cat > "$TMP/bad.sh" <<'EOF'
#!/bin/bash
stop_safe() {
  echo "[STOP-SAFE] $1" >&2
  exit 1
}
stop_danger() {
  echo "[STOP-DANGER] $1" >&2
  exit 1
}
stop_safe "Branch mismatch: on 'a', lock expects 'b'."
EOF
out=$(bash "$LINT" "$TMP/bad.sh" 2>&1); rc=$?
[[ $rc -ne 0 ]] && pass "E-G-lint-1:non-zero exit" || fail "E-G-lint-1:non-zero exit" "rc=$rc out=$out"
assert_contains "E-G-lint-1:Tier mismatch reported" "Tier mismatch" "$out"

# E-G-lint-detached — flip stop_danger → stop_safe on Detached HEAD site.
new_scenario "E-G-lint-2: detached-HEAD site mistagged → lint fails"
TMP=$(mktemp -d); record_temp "$TMP"
/bin/cat > "$TMP/bad.sh" <<'EOF'
#!/bin/bash
stop_safe() {
  echo "[STOP-SAFE] $1" >&2
  exit 1
}
stop_danger() {
  echo "[STOP-DANGER] $1" >&2
  exit 1
}
stop_safe "Detached HEAD inside locked worktree (no override available)."
EOF
out=$(bash "$LINT" "$TMP/bad.sh" 2>&1); rc=$?
[[ $rc -ne 0 ]] && pass "E-G-lint-2:non-zero exit" || fail "E-G-lint-2:non-zero exit" "rc=$rc out=$out"
assert_contains "E-G-lint-2:Tier mismatch reported" "Tier mismatch" "$out"

# E-G-lint-missing-field — flip stop_danger → stop_safe on missing-field site.
new_scenario "E-G-lint-3: current_branch_at_phase_0 missing mistagged → lint fails"
TMP=$(mktemp -d); record_temp "$TMP"
/bin/cat > "$TMP/bad.sh" <<'EOF'
#!/bin/bash
echo "[STOP-SAFE] current_branch_at_phase_0 missing from Phase 0 JSON output." >&2
exit 1
EOF
out=$(bash "$LINT" "$TMP/bad.sh" 2>&1); rc=$?
[[ $rc -ne 0 ]] && pass "E-G-lint-3:non-zero exit" || fail "E-G-lint-3:non-zero exit" "rc=$rc out=$out"
assert_contains "E-G-lint-3:Tier mismatch reported" "Tier mismatch" "$out"

# ---------------------------------------------------------------------------
# Summary
echo
if (( FAILED == 0 )); then
  echo "PASS phase-0-preflight tests ($PASSED ok)"
  exit 0
else
  echo "FAIL phase-0-preflight tests ($PASSED ok, $FAILED failed)"
  exit 1
fi
