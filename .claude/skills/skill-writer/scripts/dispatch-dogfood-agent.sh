#!/usr/bin/env bash
# dispatch-dogfood-agent.sh — resident-dogfood Behavior-depth preparer.
#
# Sibling of dispatch-e2e-baseline-agent.sh (Open Question 1 DECIDED: a SIBLING, not an
# extension — e2e-baseline-agent is rewrite-AB-specific and overloading it would yield a
# four-not-like abstraction). This preparer wires skill-writer onto the PR1
# resident-run contract (docs/dogfoods/README.md Part 2).
#
# It is the MANDATORY first step of every resident run (Open Q4): it allocates
# the monotonic run id BEFORE any Behavior dispatch, so run-id numbering and the
# dispatch prompt stay comparable across runs.
#
# It:
#   1. Computes the next free run-NNN under docs/dogfoods/<skill>/run-NNN/
#      (cumulative, never-reuse — mirrors e2e-baseline-agent's iteration auto-detect).
#   2. Creates run-NNN/{inputs,behavior}/.
#   3. Writes a BYTE-STABLE behavior/dispatch-prompt.md. The prompt is a pure
#      function of (skill-name, task) ONLY — it deliberately contains NO run id,
#      date, $RANDOM, or absolute tmp path, so re-running the preparer for the
#      same skill+task produces a byte-identical prompt (Open Q2).
#   4. Snapshots the task to inputs/task.md.
#   5. Prints the dispatch prompt for the main agent to spawn the Behavior agent.
#
# It NEVER spawns the agent itself — bash cannot invoke the Agent tool; the main
# agent dispatches (consistent with dispatch-e2e-baseline-agent.sh).
#
# Usage:
#   dispatch-dogfood-agent.sh <skill-path> [--task <text>] [--run <NNN>]
#   dispatch-dogfood-agent.sh --help
#
# Exit codes:
#   0  success
#   1  bad args
#   2  skill-path not found OR missing SKILL.md
#   3  run-id limit exceeded (> 999)

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: dispatch-dogfood-agent.sh <skill-path> [--task <text>] [--run <NNN>]
       dispatch-dogfood-agent.sh --help

Resident-dogfood Behavior-depth preparer (sibling of dispatch-e2e-baseline-agent.sh).
Allocates the next free run-NNN under docs/dogfoods/<skill>/run-NNN/, creates
inputs/+behavior/, writes a BYTE-STABLE behavior/dispatch-prompt.md, and prints
the dispatch prompt template. It does NOT spawn the agent (the main agent does).

Options:
  <skill-path>     Required positional. Path to the skill directory to exercise.
                   Must contain SKILL.md.
  --task <text>    Optional. The controlled task the Behavior agent runs the
                   skill on. Default: a generic representative-task string.
                   The (skill, task) pair fully determines the byte-stable
                   dispatch prompt.
  --run <NNN>      Optional. Force a specific run number (1..999).
                   Default: auto-detect next free NNN.
  --help           Print this help and exit 0.

Exit codes:
  0  success
  1  bad args
  2  skill-path not found or missing SKILL.md
  3  run-id limit exceeded (> 999)
USAGE
}

# --- arg parsing ---
if [[ $# -eq 0 ]]; then
  usage >&2
  exit 1
fi

SKILL_PATH=""
RUN=""
TASK=""
TASK_SET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --task)
      TASK="${2:-}"
      if [[ -z "$TASK" ]]; then
        echo "dispatch-dogfood-agent: --task requires an argument" >&2
        exit 1
      fi
      TASK_SET=1
      shift 2
      ;;
    --run)
      RUN="${2:-}"
      if [[ -z "$RUN" ]]; then
        echo "dispatch-dogfood-agent: --run requires a numeric argument" >&2
        exit 1
      fi
      shift 2
      ;;
    -*)
      echo "dispatch-dogfood-agent: unknown flag '$1'" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "$SKILL_PATH" ]]; then
        echo "dispatch-dogfood-agent: only one <skill-path> allowed" >&2
        exit 1
      fi
      SKILL_PATH="$1"
      shift
      ;;
  esac
done

if [[ -z "$SKILL_PATH" ]]; then
  echo "dispatch-dogfood-agent: <skill-path> is required" >&2
  usage >&2
  exit 1
fi

# Default task — a fixed string so the prompt stays byte-stable when --task is
# omitted (determinism over cleverness).
if [[ "$TASK_SET" -eq 0 ]]; then
  TASK="Run this skill's full flow on a representative real task for its primary trigger."
fi

# --- validate skill-path ---
if [[ ! -d "$SKILL_PATH" ]]; then
  echo "dispatch-dogfood-agent: skill-path '$SKILL_PATH' is not a directory" >&2
  exit 2
fi
if [[ ! -f "$SKILL_PATH/SKILL.md" ]]; then
  echo "dispatch-dogfood-agent: '$SKILL_PATH/SKILL.md' not found" >&2
  exit 2
fi

# --- resolve names ---
SKILL_PATH_ABS="$(cd "$SKILL_PATH" && pwd)"
SKILL_NAME="$(basename "$SKILL_PATH_ABS")"

# The skill name becomes the trace `target=<skill>` field and a path segment
# under docs/dogfoods/. Constrain it to [A-Za-z0-9_-]+ so the read-side
# `sed 's/.* target=\([^ ]*\) .*/.../'` parse stays unambiguous (no spaces /
# shell metacharacters / path traversal in the trace line).
if ! [[ "$SKILL_NAME" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "dispatch-dogfood-agent: skill name '$SKILL_NAME' must match [A-Za-z0-9_-]+ (it becomes the trace target= field)" >&2
  exit 1
fi

# Resolve repo root by walking up to the directory containing .git/ (canonical
# repo-root signal) OR docs/dogfoods/ (secondary signal, present once evidence
# exists). Fall back to the skill's parent if neither is found (detached
# worktree). Mirrors dispatch-e2e-baseline-agent.sh exactly.
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

# Resident path: NO -vN suffix (that suffix is what distinguishes a rewrite path
# from a resident path — see docs/dogfoods/README.md Coexistence).
DOGFOOD_DIR="$REPO_ROOT/docs/dogfoods/${SKILL_NAME}"
mkdir -p "$DOGFOOD_DIR"

# --- determine run number ---
if [[ -z "$RUN" ]]; then
  LAST_N=0
  if compgen -G "$DOGFOOD_DIR/run-*" > /dev/null; then
    LAST_N=$(ls -1d "$DOGFOOD_DIR"/run-* 2>/dev/null \
      | sed 's|.*/run-||' \
      | grep -E '^[0-9]+$' \
      | sort -n \
      | tail -1)
    LAST_N="${LAST_N:-0}"
    # strip leading zeros for arithmetic
    LAST_N=$((10#$LAST_N))
  fi
  RUN=$((LAST_N + 1))
fi

# Validate run is numeric and in range
if ! [[ "$RUN" =~ ^[0-9]+$ ]]; then
  echo "dispatch-dogfood-agent: --run must be numeric (got '$RUN')" >&2
  exit 1
fi
RUN=$((10#$RUN))
if (( RUN > 999 )); then
  echo "dispatch-dogfood-agent: run $RUN exceeds limit (999)" >&2
  exit 3
fi

RUN_ID="$(printf 'run-%03d' "$RUN")"
RUN_DIR="$DOGFOOD_DIR/$RUN_ID"

if [[ -d "$RUN_DIR" ]]; then
  echo "dispatch-dogfood-agent: run dir already exists at $RUN_DIR" >&2
  echo "  Pass --run <NNN> with a free number; never reuse a run id." >&2
  exit 1
fi

mkdir -p "$RUN_DIR/inputs" "$RUN_DIR/behavior"

# Snapshot the task into inputs/ so the run is reproducible.
printf '%s\n' "$TASK" > "$RUN_DIR/inputs/task.md"

# --- write the BYTE-STABLE dispatch prompt ---
# CRITICAL: this file is a pure function of (SKILL_NAME, TASK). It must NOT
# contain the run id, a date, $RANDOM, or any absolute path — anything that
# varies run-to-run would break byte-stability (Open Q2) and make Behavior
# reports incomparable.
PROMPT_FILE="$RUN_DIR/behavior/dispatch-prompt.md"
cat > "$PROMPT_FILE" <<PROMPT
# Behavior-depth dogfood — $SKILL_NAME

You are the Behavior-depth dogfood agent for the skill '$SKILL_NAME'.

Behavior depth = run the skill flow IN FULL on the controlled task below and
record what actually happens — especially where documented behaviour diverges
from real behaviour, and every point where the flow STOPs. This complements
verify-skill (which only reads-and-scores SKILL.md); your job is to catch the
"reads fine but breaks when actually run" class.

## Controlled task

$TASK

## What to do

1. Invoke '$SKILL_NAME' on the controlled task above, following its SKILL.md
   exactly as written. Do NOT improvise around documented steps.
2. As you go, note every STOP point and every place where the documented
   behaviour does not match what actually happens.

## What to report

Write two files into the run's behavior/ directory:

- report.md — your full-flow run transcript: each phase/step, the command or
  action, and the observed result.
- gaps.md   — one bullet per doc-vs-behaviour divergence or STOP point, each
  with: the documented expectation, the observed behaviour, and the impact.

Report only what you observed. Do NOT speculate about fixes or redesigns.
PROMPT

# --- print dispatch instruction ---
cat <<INSTR

dispatch-dogfood-agent: resident run ready

  run dir:        $RUN_DIR
  run id:         $RUN_ID
  skill:          $SKILL_NAME
  dispatch prompt: $PROMPT_FILE (byte-stable)

Next step — dispatch the Behavior-depth agent with the prompt below. This
preparer does NOT spawn it (bash cannot invoke the Agent tool); the main agent
dispatches. After the agent runs, it writes report.md + gaps.md into:
  $RUN_DIR/behavior/

----- machine-readable handoff (eval in the main agent to fill the trace) -----
DOGFOOD_TARGET=$SKILL_NAME
DOGFOOD_RUN=$RUN
----- end handoff -----

The dogfood completion trace the main agent writes (skill-writer/SKILL.md
Phase 6) MUST carry \`target=\$DOGFOOD_TARGET\` so the boundary assert cross-checks
docs/dogfoods/\$DOGFOOD_TARGET/run-NNN (the dir created above), NOT skill-writer/.

----- Behavior dogfood prompt (byte-stable; from $PROMPT_FILE) -----

$(cat "$PROMPT_FILE")

----- End prompt -----

Resident dogfood is an OPTIONAL Behavior-depth complement to verify-skill, NOT a
replacement. verify-skill (skill-writer Phase 6) remains the mandatory gate.
INSTR

exit 0
