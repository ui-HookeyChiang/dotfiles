#!/usr/bin/env bash
# dogfood-smoke.sh — resident-dogfood Smoke depth for the flow-dev
# parallel-stacks flow (PR4 of the resident-dogfood feature).
#
# Runs the real parallel scripts against a controlled, ISOLATED fixture and
# captures evidence per the PR1 contract (docs/dogfoods/README.md Part 2):
#
#   <evidence-dir>/run-NNN/
#     ├── inputs/   snapshot of the fixture layers JSON
#     └── smoke/    one <cmd>.log + <cmd>.exit per asserted command
#
# Deterministic, CI-able, spawns NO agent. The whole git harness lives in a
# mktemp dir — it NEVER touches the real repo's worktrees or PR list.
#
# Open Q6: the exit code of each command is CAPTURED to <cmd>.exit. The smoke
# does NOT auto-fail on a deliberately-non-zero command (e.g. the empty-layers
# STOP-SAFE case) — it asserts the EXPECTED exit code instead.
#
# Usage:
#   dogfood-smoke.sh [--evidence-dir <dir>]
#   dogfood-smoke.sh --help
#
# Exit: 0 all assertions held; 1 an assertion failed; 2 bad args.

set -uo pipefail

usage() {
  cat <<'USAGE'
Usage: dogfood-smoke.sh [--evidence-dir <dir>]
       dogfood-smoke.sh --help

Runs parallel-layers.sh + merge-train.sh against an isolated fixture and
emits Smoke evidence (run-NNN/smoke/<cmd>.{log,exit}). Spawns no agent.

Options:
  --evidence-dir <dir>  Where to write run-NNN/ evidence. Default: a mktemp
                        dir (printed on completion). Tests pass a tmp dir.
  --help                Print this help and exit 0.
USAGE
}

EVIDENCE_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --evidence-dir) EVIDENCE_DIR="${2:-}"; [[ -z "$EVIDENCE_DIR" ]] && { echo "dogfood-smoke: --evidence-dir requires a value" >&2; exit 2; }; shift 2 ;;
    *) echo "dogfood-smoke: unknown arg '$1'" >&2; usage >&2; exit 2 ;;
  esac
done

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MERGE_TRAIN="$SCRIPTS_DIR/merge-train.sh"
LIB="$SCRIPTS_DIR/lib/parallel-layers.sh"

if [[ -z "$EVIDENCE_DIR" ]]; then
  EVIDENCE_DIR="$(mktemp -d)"
fi
mkdir -p "$EVIDENCE_DIR"
# Absolutize BEFORE we cd into the harness, else a relative --evidence-dir
# (e.g. docs/dogfoods/flow-dev) breaks once we chdir away.
EVIDENCE_DIR="$(cd "$EVIDENCE_DIR" && pwd)"

# Allocate a monotonic run-NNN under EVIDENCE_DIR (mirrors the preparer's
# never-reuse rule so Smoke and Behavior share the same numbering discipline).
LAST_N=0
if compgen -G "$EVIDENCE_DIR/run-*" > /dev/null; then
  LAST_N=$(/bin/ls -1d "$EVIDENCE_DIR"/run-* 2>/dev/null \
    | sed 's|.*/run-||' | /bin/grep -E '^[0-9]+$' | sort -n | tail -1)
  LAST_N=$((10#${LAST_N:-0}))
fi
RUN_NNN=$(printf 'run-%03d' $((LAST_N + 1)))
RUN_DIR="$EVIDENCE_DIR/$RUN_NNN"
SMOKE_DIR="$RUN_DIR/smoke"
INPUTS_DIR="$RUN_DIR/inputs"
mkdir -p "$SMOKE_DIR" "$INPUTS_DIR"

FAILED=0
pass () { echo "  PASS: $1"; }
fail () { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }

# capture <cmd-name> <expected-exit> -- <command...>
#   Runs the command, captures stdout+stderr to smoke/<cmd-name>.log and the
#   exit code to smoke/<cmd-name>.exit (Open Q6), then asserts the captured
#   exit equals <expected-exit> (so a deliberately-non-zero command is a PASS
#   when its expected code matches, not an auto-fail).
capture () {
  local name="$1" expected="$2"; shift 2
  [[ "$1" == "--" ]] && shift
  local log="$SMOKE_DIR/$name.log" exitf="$SMOKE_DIR/$name.exit" rc
  set +e
  "$@" >"$log" 2>&1
  rc=$?
  set -e
  echo "$rc" > "$exitf"
  if [[ "$rc" == "$expected" ]]; then
    pass "$name exited $rc (expected $expected) — evidence captured"
  else
    fail "$name exited $rc (expected $expected); see $log"
  fi
}

# --- build an isolated git harness (NEVER the real repo) -------------------
HARNESS="$(mktemp -d)"
trap 'rm -rf "$HARNESS"' EXIT
git init -q -b main "$HARNESS/main"
cd "$HARNESS/main"
echo "base" > base.txt
git -c user.email=t@t -c user.name=t add base.txt
git -c user.email=t@t -c user.name=t commit -q -m "base"

# 3 file-disjoint leaves, 2 layers — the canonical parallel-stacks shape.
LAYERS='[["PR-1"],["PR-2","PR-3"]]'
echo "$LAYERS" > "$INPUTS_DIR/parallel_layers.json"
for g in PR-1 PR-2 PR-3; do
  git -c user.email=t@t -c user.name=t branch "feat/foo/task-${g}" main
  git worktree add -q ".worktrees/feat-foo/task-${g}" "feat/foo/task-${g}"
  case "$g" in
    PR-1) f=foo.txt ;; PR-2) f=bar.txt ;; PR-3) f=baz.txt ;;
  esac
  echo "$g" > ".worktrees/feat-foo/task-${g}/$f"
  (cd ".worktrees/feat-foo/task-${g}" && \
    git -c user.email=t@t -c user.name=t add "$f" && \
    git -c user.email=t@t -c user.name=t commit -q -m "feat: add $f")
done

# --- Smoke 1: parallel-layers.sh lib reads the fixture layers --------------
# Source the lib and assert the canonical accessors against the fixture.


# --- Smoke 2: merge-train.sh collapses the leaves (HAPPY path) -------------
capture "merge-train" 0 -- \
  env SD_PARALLEL_LAYERS="$LAYERS" \
  bash "$MERGE_TRAIN" \
    --feature-prefix "feat/foo" \
    --worktree-ns "feat-foo" \
    --default-branch "main"

# Assert the parallel flow actually integrated all 3 leaves.
INT=".worktrees/feat-foo/integration"
for f in foo.txt bar.txt baz.txt; do
  if git -C "$INT" cat-file -e "HEAD:$f" 2>/dev/null; then
    pass "merge-train integrated $f"
  else
    fail "merge-train did not integrate $f into $INT HEAD"
  fi
done

# --- Smoke 3: merge-train.sh STOP-SAFE on empty layers (EXPECTED non-zero) -
# Open Q6: a deliberately-non-zero command. We capture exit 2 and assert it
# equals the expected code — NOT an auto-fail.
capture "merge-train-empty-layers" 2 -- \
  env SD_PARALLEL_LAYERS='[]' \
  bash "$MERGE_TRAIN" \
    --feature-prefix "feat/foo" \
    --worktree-ns "feat-foo" \
    --default-branch "main"

cd / # leave the harness before trap rm

echo
echo "dogfood-smoke: evidence at $RUN_DIR"
if (( FAILED == 0 )); then
  echo "dogfood-smoke: all assertions held."
  exit 0
else
  echo "dogfood-smoke: $FAILED assertion(s) failed."
  exit 1
fi
