#!/usr/bin/env bash
# dispatch-e2e-baseline-agent.sh — Phase 0 E2E Baseline snapshot + dispatch helper.
#
# Snapshots a v1 skill into docs/dogfoods/<skill-name>-v2/iteration-N/v1-snapshot/
# (cumulative numbering; auto-detects next free N) and prints the Agent Baseline
# dispatch prompt template for the user to paste into a sub-agent.
#
# This script does NOT spawn the agent itself — bash cannot invoke the
# Agent tool. It prepares the snapshot and prints the instruction.
#
# Usage:
#   dispatch-e2e-baseline-agent.sh <skill-path> [--iteration <N>]
#   dispatch-e2e-baseline-agent.sh --help
#
# Exit codes:
#   0  success
#   1  bad args
#   2  skill-path not found OR missing SKILL.md
#   3  iteration limit exceeded (> 99)

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: dispatch-e2e-baseline-agent.sh <skill-path> [--iteration <N>]
       dispatch-e2e-baseline-agent.sh --help

Snapshots <skill-path>/* into docs/dogfoods/<skill-name>-v2/iteration-N/v1-snapshot/
(auto-detects next free N if --iteration not given) and prints the Agent Baseline
dispatch prompt template.

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
        echo "dispatch-e2e-baseline-agent: --iteration requires a numeric argument" >&2
        exit 1
      fi
      shift 2
      ;;
    -*)
      echo "dispatch-e2e-baseline-agent: unknown flag '$1'" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "$SKILL_PATH" ]]; then
        echo "dispatch-e2e-baseline-agent: only one <skill-path> allowed" >&2
        exit 1
      fi
      SKILL_PATH="$1"
      shift
      ;;
  esac
done

if [[ -z "$SKILL_PATH" ]]; then
  echo "dispatch-e2e-baseline-agent: <skill-path> is required" >&2
  usage >&2
  exit 1
fi

# --- validate skill-path ---
if [[ ! -d "$SKILL_PATH" ]]; then
  echo "dispatch-e2e-baseline-agent: skill-path '$SKILL_PATH' is not a directory" >&2
  exit 2
fi
if [[ ! -f "$SKILL_PATH/SKILL.md" ]]; then
  echo "dispatch-e2e-baseline-agent: '$SKILL_PATH/SKILL.md' not found" >&2
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
  # Auto-detect next free N
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
  echo "dispatch-e2e-baseline-agent: --iteration must be numeric (got '$ITERATION')" >&2
  exit 1
fi
if (( ITERATION > 99 )); then
  echo "dispatch-e2e-baseline-agent: iteration $ITERATION exceeds limit (99)" >&2
  exit 3
fi

ITER_DIR="$DOGFOOD_DIR/iteration-$ITERATION"
SNAPSHOT_DIR="$ITER_DIR/v1-snapshot"

if [[ -d "$SNAPSHOT_DIR" ]]; then
  echo "dispatch-e2e-baseline-agent: snapshot already exists at $SNAPSHOT_DIR" >&2
  echo "  Pass --iteration <N> with a free number, or delete the existing dir." >&2
  exit 1
fi

mkdir -p "$SNAPSHOT_DIR"
cp -r "$SKILL_PATH_ABS"/* "$SNAPSHOT_DIR"/

# --- print dispatch instruction ---
cat <<INSTR

dispatch-e2e-baseline-agent: snapshot ready

  v1 snapshot: $SNAPSHOT_DIR
  iteration:   $ITERATION
  skill:       $SKILL_NAME

Next step — dispatch Agent Baseline with the prompt below.
Agent Baseline MUST NOT see v2 design (anchoring would invalidate the baseline).

----- Agent Baseline prompt template -----

You are Agent Baseline for Phase 0 E2E Baseline measurement of '$SKILL_NAME'.

Working directory: $SNAPSHOT_DIR
You see only the v1 snapshot. You MUST NOT search for or read any v2 draft.

Run the v1 skill against representative user requests and measure five
dimensions. Write your report to $ITER_DIR/red-report.md.

Five measurement dimensions:
  1. trigger accuracy        — true-positive % on a held-out trigger set
  2. compliance under pressure — Adversarial cave count (try 4 universal
     scenarios from skill-writer/references/adversarial-scenarios.md)
  3. token cost per invocation — output tokens
  4. time to completion       — wall-clock seconds per invocation
  5. loophole count           — fresh Adversarial-discovery rationalizations

Report format: one row per dimension with v1 value + the trial transcript
that produced it. Do NOT speculate about v2 improvements.

----- End template -----

After Agent Baseline reports, run v2 implementation, then spawn fresh Agent
REFACTOR-CHECK to measure the same 5 dimensions on v2. User compares;
auto-PASS is forbidden (see e2e-baseline-standard.md).
INSTR

exit 0
