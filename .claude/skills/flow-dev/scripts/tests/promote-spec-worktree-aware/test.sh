#!/bin/bash
# tests/promote-spec-worktree-aware/test.sh — promote-spec-to-active.sh
# contract under the only surviving backend (none).
#
# After the docs-lifecycle backend was removed, promote is a no-op: the
# dispatcher routes to _spec_backend_none_promote, which returns
# {"ok":true,"action":"skipped-none-backend"} exit 0 and performs NO git
# ops — no `mv` commit, no `set status=active` commit, no protected-branch
# guard, on any branch or worktree. The wrapper's argv contract (both
# --worktree orderings parse; bad argv -> exit 64) is preserved in the shim
# and is the only behavior still meaningfully exercised here.
#
# The old worktree-aware *promotion* assertions (commits landing on the
# linked worktree branch, two-commit mv/status split, on-main protected-
# branch refusal) tested docs-lifecycle behavior that no longer exists;
# they are rewritten to the none no-op contract (the spec stays in
# proposed/ because nothing is moved).
#
# Strategy: build a real fixture repo with `mktemp -d` + `git init` +
# `git worktree add`, invoke the real promote-spec-to-active.sh, then
# assert (a) stdout JSON shape == skipped-none-backend, (b) NO commit
# landed on either branch, (c) the spec is untouched in proposed/.
#
# Run: bash flow-dev/scripts/tests/promote-spec-worktree-aware/test.sh
#   (or via tests/run-all.sh discovery)

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$HERE/../.."
PROMOTE="$SCRIPTS/promote-spec-to-active.sh"

FAILED=0
PASSED=0

pass() { echo "  ok   $1"; PASSED=$((PASSED + 1)); }
fail() {
  echo "  FAIL $1"
  [[ -n "${2:-}" ]] && echo "       $2"
  FAILED=$((FAILED + 1))
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"
  else fail "$1" "expected='$2' actual='$3'"
  fi
}
assert_contains() {
  if [[ "$3" == *"$2"* ]]; then pass "$1"
  else fail "$1" "expected substring '$2' in: $3"
  fi
}

# Tracked temp dirs for trap cleanup.
TEMPS=()
record_temp() { TEMPS+=("$1"); }
cleanup_all() {
  local d gf wt
  cd /tmp
  for d in "${TEMPS[@]:-}"; do
    if [[ -n "$d" && -d "$d" ]]; then
      # Prune any worktrees so their links don't keep the dir read-only.
      while IFS= read -r gf; do
        wt=$(dirname "$gf")
        git -C "$wt" worktree prune 2>/dev/null || true
      done < <(find "$d" -name ".git" -type f 2>/dev/null)
      chmod -R u+w "$d" 2>/dev/null || true
      rm -rf "$d"
    fi
  done
}
trap cleanup_all EXIT

new_scenario() { echo; echo "=== $1 ==="; }

# Build a fixture repo with one committed proposed spec.
# Sets globals: REPO_ROOT, SLUG, SPEC_REL, DATE.
make_fixture_repo() {
  REPO_ROOT=$(mktemp -d -t sd-test-promote-XXXXXX)
  record_temp "$REPO_ROOT"
  DATE="2026-05-24"
  SLUG="test-feature-$(printf '%04x' $RANDOM)"
  SPEC_REL="docs/specs/proposed/${DATE}-${SLUG}.md"

  cd "$REPO_ROOT"
  git init -q -b main .
  git config user.email "test@example.com"
  git config user.name "Test User"
  /bin/cat > .docs-lifecycle.json <<'JSON'
{
  "version": 5,
  "specs": {"proposed": "docs/specs/proposed/", "active": "docs/specs/active/", "done": "docs/specs/done/"},
  "decisions": "docs/decisions/",
  "naming": {"pattern": "YYYY-MM-DD-<slug>.md", "plan_suffix": "-plan.md"},
  "tracking": {"todo_file": "TODO.md"},
  "frontmatter": {"kind_field": "kind", "status_field": "status", "spec_kind": "spec", "decision_kind": "decision"},
  "jira": {"uses_jira": false, "project": null, "detected_from": null, "configured_at": null, "default_strategy": "ask"}
}
JSON
  mkdir -p docs/specs/proposed docs/specs/active docs/specs/done
  /bin/cat > "$SPEC_REL" <<EOF
---
title: "${SLUG}"
kind: spec
date: ${DATE}
status: proposed
---

# Spec — ${SLUG}

## Purpose
Fixture spec for promote-spec-worktree-aware test.
EOF
  git add .docs-lifecycle.json "$SPEC_REL"
  git commit -q -m "fixture: seed proposed spec ${SLUG}"
}

# Add a linked worktree at <REPO_ROOT>/.wt-linked with branch feat/${SLUG}-wt.
# Sets globals: WT_LINKED, WT_BRANCH.
add_linked_worktree() {
  WT_LINKED="$REPO_ROOT/.wt-linked"
  WT_BRANCH="feat/${SLUG}-wt"
  git -C "$REPO_ROOT" worktree add -q -b "$WT_BRANCH" "$WT_LINKED" main
}

# ---------------------------------------------------------------------------
# Case (a): ordering 1 — `<slug> --worktree <wt>`. Under none the flag still
# parses (both orderings) but promote is a no-op: skipped-none-backend, exit
# 0, no commit on the worktree branch OR main, spec untouched in proposed/.
new_scenario "ordering-1: <slug> --worktree <wt> (none no-op)"
make_fixture_repo
add_linked_worktree
ACTIVE_REL="docs/specs/active/${DATE}-${SLUG}.md"
# Invoke from REPO_ROOT (main checkout); --worktree points at the linked wt.
out=$(cd "$REPO_ROOT" && bash "$PROMOTE" "$SLUG" --worktree "$WT_LINKED" 2>/dev/null); rc=$?
assert_eq "ord1:exit" 0 "$rc"
# stdout must be a single line of JSON with ok=true, action=skipped-none-backend.
ok=$(printf '%s' "$out" | jq -r '.ok' 2>/dev/null || echo "ERR")
action=$(printf '%s' "$out" | jq -r '.action' 2>/dev/null || echo "ERR")
slug_out=$(printf '%s' "$out" | jq -r '.slug' 2>/dev/null || echo "ERR")
assert_eq "ord1:.ok" "true" "$ok"
assert_eq "ord1:.action" "skipped-none-backend" "$action"
assert_eq "ord1:.slug" "$SLUG" "$slug_out"
# No commit landed on the linked worktree branch (promote did no git ops).
wt_log=$(git -C "$WT_LINKED" log --format=%s -- "$ACTIVE_REL" 2>/dev/null || true)
assert_eq "ord1:wt has no commit" "" "$wt_log"
# Nothing landed on main either.
main_subj=$(git -C "$REPO_ROOT" log -1 --format=%s -- "$ACTIVE_REL" 2>/dev/null || true)
assert_eq "ord1:main has no commit" "" "$main_subj"
# Spec untouched in proposed/ (not moved to active/).
[[ -f "$REPO_ROOT/$SPEC_REL" ]] \
  && pass "ord1:spec still in proposed/" \
  || fail "ord1:spec still in proposed/" "spec was moved under none no-op"

# ---------------------------------------------------------------------------
# Case (b): ordering 2 — `--worktree <wt> <slug>`. Same none no-op contract;
# this case proves the reversed argv ordering still parses to exit 0.
new_scenario "ordering-2: --worktree <wt> <slug> (none no-op)"
make_fixture_repo
add_linked_worktree
ACTIVE_REL="docs/specs/active/${DATE}-${SLUG}.md"
out=$(cd "$REPO_ROOT" && bash "$PROMOTE" --worktree "$WT_LINKED" "$SLUG" 2>/dev/null); rc=$?
assert_eq "ord2:exit" 0 "$rc"
ok=$(printf '%s' "$out" | jq -r '.ok' 2>/dev/null || echo "ERR")
action=$(printf '%s' "$out" | jq -r '.action' 2>/dev/null || echo "ERR")
assert_eq "ord2:.ok" "true" "$ok"
assert_eq "ord2:.action" "skipped-none-backend" "$action"
wt_log=$(git -C "$WT_LINKED" log --format=%s -- "$ACTIVE_REL" 2>/dev/null || true)
assert_eq "ord2:wt has no commit" "" "$wt_log"
main_subj=$(git -C "$REPO_ROOT" log -1 --format=%s -- "$ACTIVE_REL" 2>/dev/null || true)
assert_eq "ord2:main has no commit" "" "$main_subj"

# ---------------------------------------------------------------------------
# Case (c): no --worktree flag, single worktree. Under none, promote no-ops
# regardless of the current branch (no protected-branch guard, no commits).
new_scenario "no-flag single worktree (none no-op)"
make_fixture_repo
git -C "$REPO_ROOT" checkout -q -b "feat/${SLUG}-promote"
ACTIVE_REL="docs/specs/active/${DATE}-${SLUG}.md"
out=$(cd "$REPO_ROOT" && bash "$PROMOTE" "$SLUG" 2>/dev/null); rc=$?
assert_eq "noflag:exit" 0 "$rc"
action=$(printf '%s' "$out" | jq -r '.action' 2>/dev/null || echo "ERR")
assert_eq "noflag:.action" "skipped-none-backend" "$action"
# No commit on the current branch (promote did nothing).
cur_log=$(git -C "$REPO_ROOT" log --format=%s -- "$ACTIVE_REL" 2>/dev/null || true)
assert_eq "noflag:current branch has no commit" "" "$cur_log"

# ---------------------------------------------------------------------------
# Case (d): --worktree missing path → exit 64 + stderr names the error.
new_scenario "edge: --worktree without path argument"
make_fixture_repo
err=$(cd "$REPO_ROOT" && bash "$PROMOTE" "$SLUG" --worktree 2>&1 >/dev/null); rc=$?
assert_eq "edge-missing-path:exit" 64 "$rc"
assert_contains "edge-missing-path:stderr" \
  "--worktree requires a path argument" "$err"

# ---------------------------------------------------------------------------
# Case (e): unknown flag → exit 64 + stderr says "unknown flag".
new_scenario "edge: unknown flag"
make_fixture_repo
err=$(cd "$REPO_ROOT" && bash "$PROMOTE" --unknown "$SLUG" 2>&1 >/dev/null); rc=$?
assert_eq "edge-unknown-flag:exit" 64 "$rc"
assert_contains "edge-unknown-flag:stderr" "unknown flag" "$err"

# ---------------------------------------------------------------------------
# Case (f): on `main` with no --worktree. The old docs-lifecycle protected-
# branch guard (issue #623: refuse promote on main with exit 1) is gone with
# the backend. Under none, promote no-ops on any branch: exit 0,
# skipped-none-backend, no "protected branch" stderr, spec left in proposed/.
new_scenario "on-main: none no-op (no protected-branch guard)"
make_fixture_repo  # fixture is on branch main by default
out=$(cd "$REPO_ROOT" && bash "$PROMOTE" "$SLUG" 2>/tmp/promote_onmain.$$.err); rc=$?
err=$(/bin/cat /tmp/promote_onmain.$$.err 2>/dev/null); rm -f /tmp/promote_onmain.$$.err
assert_eq "on-main:exit" 0 "$rc"
action=$(printf '%s' "$out" | jq -r '.action' 2>/dev/null || echo "ERR")
assert_eq "on-main:.action" "skipped-none-backend" "$action"
case "$err" in
  *"protected branch"*)
    fail "on-main:no protected-branch stderr" "guard fired under none: $err" ;;
  *)
    pass "on-main:no protected-branch stderr (guard removed with backend)" ;;
esac
# Spec stayed in proposed/ (no commit happened).
[[ -f "$REPO_ROOT/docs/specs/proposed/${DATE}-${SLUG}.md" ]] \
  && pass "on-main:spec still in proposed/" \
  || fail "on-main:spec still in proposed/" "spec was moved under none no-op"

# ---------------------------------------------------------------------------
# Summary
echo
if (( FAILED == 0 )); then
  echo "PASS promote-spec-worktree-aware tests ($PASSED ok)"
  exit 0
else
  echo "FAIL promote-spec-worktree-aware tests ($PASSED ok, $FAILED failed)"
  exit 1
fi
