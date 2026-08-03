#!/usr/bin/env bash
# dispatch-expectation-acceptance-agent.sh — INTENT expectation-spec freeze + TEST acceptance helper.
#
# Allocates the iteration directory, writes a blank expectation-spec template, and
# prints the acceptance-agent dispatch prompt for the user to paste into a sub-agent.
#
# This script does NOT spawn the agent itself — bash cannot invoke the
# Agent tool. It prepares the directory structure and prints the instruction.
#
# Usage:
#   dispatch-expectation-acceptance-agent.sh <skill-path> [--iteration <N>]
#   dispatch-expectation-acceptance-agent.sh --help
#
# Exit codes:
#   0  success
#   1  bad args
#   2  skill-path not found OR missing SKILL.md
#   3  iteration limit exceeded (> 99)

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: dispatch-expectation-acceptance-agent.sh <skill-path> [--iteration <N>]
       dispatch-expectation-acceptance-agent.sh --help

Allocates docs/dogfoods/<skill-name>-v2/iteration-N/ (auto-detects next free N if
--iteration not given), writes a blank expectation-spec.md template, and prints the
acceptance-agent dispatch prompt.

Options:
  <skill-path>        Required positional. Path to the v1 skill directory.
                      Must contain SKILL.md.
  --iteration <N>     Optional. Force a specific iteration number (1..99).
                      Default: auto-detect next free N.
  --help              Print this help and exit 0.

Exit codes:
  0  success
  1  bad args
  2  skill-path not found or missing SKILL.md
  3  iteration limit exceeded (> 99)
USAGE
}

# --- arg parsing ---
if [[ $# -eq 0 ]]; then
  usage >&2
  exit 1
fi

SKILL_PATH=""
ITERATION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --iteration)
      ITERATION="${2:-}"
      if [[ -z "$ITERATION" ]]; then
        echo "dispatch-expectation-acceptance-agent: --iteration requires a numeric argument" >&2
        exit 1
      fi
      shift 2
      ;;
    -*)
      echo "dispatch-expectation-acceptance-agent: unknown flag '$1'" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "$SKILL_PATH" ]]; then
        echo "dispatch-expectation-acceptance-agent: only one <skill-path> allowed" >&2
        exit 1
      fi
      SKILL_PATH="$1"
      shift
      ;;
  esac
done

if [[ -z "$SKILL_PATH" ]]; then
  echo "dispatch-expectation-acceptance-agent: <skill-path> is required" >&2
  usage >&2
  exit 1
fi

# --- validate skill-path ---
if [[ ! -d "$SKILL_PATH" ]]; then
  echo "dispatch-expectation-acceptance-agent: skill-path '$SKILL_PATH' is not a directory" >&2
  exit 2
fi
if [[ ! -f "$SKILL_PATH/SKILL.md" ]]; then
  echo "dispatch-expectation-acceptance-agent: '$SKILL_PATH/SKILL.md' not found" >&2
  exit 2
fi

# --- resolve names ---
SKILL_PATH_ABS="$(cd "$SKILL_PATH" && pwd)"
SKILL_NAME="$(basename "$SKILL_PATH_ABS")"

# Resolve repo root by walking up to the directory containing .git/ (the
# canonical repo-root signal) OR docs/dogfoods/ (secondary signal, present
# once evidence has been written). Fall back to the skill's parent if neither
# is found (e.g. a detached worktree with no .git at the expected level).
REPO_ROOT="$SKILL_PATH_ABS"
while [[ "$REPO_ROOT" != "/" ]]; do
  if [[ -d "$REPO_ROOT/.git" || -d "$REPO_ROOT/docs/dogfoods" ]]; then
    break
  fi
  REPO_ROOT="$(dirname "$REPO_ROOT")"
done
if [[ "$REPO_ROOT" == "/" ]]; then
  REPO_ROOT="$(dirname "$SKILL_PATH_ABS")"
fi

DOGFOOD_DIR="$REPO_ROOT/docs/dogfoods/${SKILL_NAME}-v2"
mkdir -p "$DOGFOOD_DIR"

# --- determine iteration number ---
if [[ -z "$ITERATION" ]]; then
  LAST_N=0
  if compgen -G "$DOGFOOD_DIR/iteration-*" > /dev/null; then
    LAST_N=$(ls -1d "$DOGFOOD_DIR"/iteration-* 2>/dev/null \
      | sed 's|.*/iteration-||' \
      | grep -E '^[0-9]+$' \
      | sort -n \
      | tail -1)
    LAST_N="${LAST_N:-0}"
  fi
  ITERATION=$((LAST_N + 1))
fi

# Validate iteration is numeric and in range
if ! [[ "$ITERATION" =~ ^[0-9]+$ ]]; then
  echo "dispatch-expectation-acceptance-agent: --iteration must be numeric (got '$ITERATION')" >&2
  exit 1
fi
if (( ITERATION > 99 )); then
  echo "dispatch-expectation-acceptance-agent: iteration $ITERATION exceeds limit (99)" >&2
  exit 3
fi

ITER_DIR="$DOGFOOD_DIR/iteration-$ITERATION"
SPEC_FILE="$ITER_DIR/expectation-spec.md"

if [[ -f "$SPEC_FILE" ]]; then
  echo "dispatch-expectation-acceptance-agent: spec already exists at $SPEC_FILE" >&2
  echo "  Pass --iteration <N> with a free number, or delete the existing file." >&2
  exit 1
fi

mkdir -p "$ITER_DIR"

TODAY="$(date -u +%Y-%m-%d)"
cat > "$SPEC_FILE" <<SPEC
# Expectation Spec — ${SKILL_NAME} v2 (iteration ${ITERATION})

Frozen: ${TODAY} | Source: origin/main HEAD
Status: DRAFT — fill in before any v2 authoring begins; freeze = no edits after

## Behavior expectations
<!-- Concrete, checkable by a fresh agent. One expectation per line. -->
- [ ] ...

## Known failures (v1) — v2 must fix these
<!-- Write each v1 failure as an explicit expectation; positive-only specs drop failure signal. -->
- [ ] v1 fails when <condition>: v2 MUST NOT fail under same condition

## Trigger-accuracy threshold
- Minimum true-positive %: __% on held-out set (≥ 8 positive cases)

## Cost expectations (only if rewrite goal includes slimming)
<!-- Omit this section if slimming is not a stated goal. -->
- Output tokens per invocation: ≤ ____
SPEC

# --- print dispatch instruction ---
cat <<INSTR

dispatch-expectation-acceptance-agent: iteration directory ready

  spec file: $SPEC_FILE
  iteration: $ITERATION
  skill:     $SKILL_NAME

NEXT STEPS — two-phase:

Phase 1 (INTENT): Fill in $SPEC_FILE now, before writing any v2 code.
  Freeze = do not edit after v2 authoring begins.

Phase 2 (TEST): After v2 is implemented, dispatch a fresh acceptance agent
  with the prompt below. Agent must NOT have seen the spec-authoring session.

----- Acceptance agent prompt template -----

You are the Expectation Acceptance agent for '$SKILL_NAME' v2.

Spec file: $SPEC_FILE
Skill (v2): $SKILL_PATH_ABS
Evidence dir: $ITER_DIR

Read the expectation spec. Run the v2 skill on representative real tasks
(do NOT read v1 skill files — contamination risk). For each expectation in
the spec, record a verdict: PASS or FAIL, with the trial evidence that
produced it.

Write your acceptance report to $ITER_DIR/acceptance-report.md.

Report format:
  ## Verdict: PASS | FAIL | PARTIAL
  ### Expectations
  | # | Expectation | Verdict | Evidence |
  |---|---|---|---|
  | 1 | ... | PASS/FAIL | brief transcript |

auto-PASS is forbidden. User reviews this report before closing the rewrite.

----- End template -----

INSTR

exit 0
