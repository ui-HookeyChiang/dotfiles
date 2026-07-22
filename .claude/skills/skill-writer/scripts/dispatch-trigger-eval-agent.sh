#!/usr/bin/env bash
# dispatch-trigger-eval-agent.sh — Phase 5 ADVISORY trigger-eval preparer.
#
# Sibling of dispatch-dogfood-agent.sh / dispatch-e2e-baseline-agent.sh. It wires
# skill-writer's authored trigger corpus (evals/trigger-eval.json) onto upstream
# skill-creator's run_eval.py — the DYNAMIC leg the flow is missing: run_eval
# spawns real `claude -p` per query and measures whether the description ACTUALLY
# causes the skill to trigger. verify-skill (Phase 6) only reads-and-SCORES the
# description statically; this preparer is the live-model complement.
#
# It is ADVISORY (non-blocking): Phase 6 verify-skill stays the binding gate.
#
# ANTI-SELF-GRADING INVARIANT: run_eval's output is NEVER wired into a description
# mutator. The moment a measure feeds an auto-rewrite, run_loop (a rejected SSOT
# Non-Goal) is rebuilt. This preparer only PRINTS the run_eval invocation; it does
# not execute it, parse its score, or feed anything back.
#
# It:
#   1. Resolves $SC_ROOT via resolve-skill-creator.sh. If the resolver exits
#      non-zero (no skill-creator install / CI), it emits a TRACED
#      verdict=skip-no-skill-creator handoff and exits 0 (advisory — never
#      hard-fails the flow).
#   2. Allocates the next free run-NNN under docs/dogfoods/<skill>/run-NNN/eval/.
#   3. Writes a BYTE-STABLE prompt file — a pure function of (skill-name, runs)
#      ONLY: NO run id, date, $RANDOM, or absolute tmp path inside it. It prints
#      the exact module-style invocation to run.
#   4. Prints a machine-readable TRIGGER_EVAL_TARGET=<skill-name> handoff line.
#   5. PRINTS the dispatch prompt; it NEVER spawns the agent (bash cannot drive
#      `claude -p`/the Agent tool — the main agent dispatches).
#
# Usage:
#   dispatch-trigger-eval-agent.sh <skill-path> [--runs <N>] [--run <NNN>]
#   dispatch-trigger-eval-agent.sh --help
#
# Exit codes:
#   0  success (incl. advisory skip-no-skill-creator / skip-no-corpus)
#   1  bad args
#   2  skill-path not found OR missing SKILL.md
#   3  run-id limit exceeded (> 999)
#
# A not-yet-authored corpus (no evals/trigger-eval.json) is a GRACEFUL advisory
# skip (verdict=skip-no-corpus, exit 0) — trigger-eval is advisory, so timing of
# corpus authoring must not hard-fail. exit 2 is reserved for caller errors:
# skill-path-not-a-dir and missing SKILL.md.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$HERE/resolve-skill-creator.sh"

usage() {
  cat <<'USAGE'
Usage: dispatch-trigger-eval-agent.sh <skill-path> [--runs <N>] [--run <NNN>]
       dispatch-trigger-eval-agent.sh --help

Phase 5 ADVISORY trigger-eval preparer (sibling of dispatch-dogfood-agent.sh).
Resolves the upstream skill-creator skill root, allocates the next free run-NNN
under docs/dogfoods/<skill>/run-NNN/eval/, writes a BYTE-STABLE dispatch prompt
that PRINTS the `cd $SC_ROOT && python3 -m scripts.run_eval ...` invocation, and
prints it. It does NOT execute run_eval and does NOT spawn the agent (the main
agent dispatches). ADVISORY — Phase 6 verify-skill stays the binding gate.

Options:
  <skill-path>     Required positional. Path to the skill directory to evaluate.
                   Must contain SKILL.md and evals/trigger-eval.json.
  --runs <N>       Optional. runs-per-query for run_eval. Default 2 (lower than
                   upstream's 3 — full 3 on demand). N in 1..99.
  --run <NNN>      Optional. Force a specific run number (1..999).
                   Default: auto-detect next free NNN.
  --help           Print this help and exit 0.

Exit codes:
  0  success (incl. advisory skip-no-skill-creator / skip-no-corpus)
  1  bad args
  2  skill-path not found / missing SKILL.md
  3  run-id limit exceeded (> 999)

A missing evals/trigger-eval.json is an advisory skip (verdict=skip-no-corpus,
exit 0), NOT exit 2 — trigger-eval is advisory; corpus-authoring timing must
not hard-fail.
USAGE
}

# --- arg parsing ---
if [[ $# -eq 0 ]]; then
  usage >&2
  exit 1
fi

SKILL_PATH=""
RUN=""
RUNS="2"   # spec: default 2, full 3 on demand
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --runs)
      RUNS="${2:-}"
      if [[ -z "$RUNS" ]]; then
        echo "dispatch-trigger-eval-agent: --runs requires a numeric argument" >&2
        exit 1
      fi
      shift 2
      ;;
    --run)
      RUN="${2:-}"
      if [[ -z "$RUN" ]]; then
        echo "dispatch-trigger-eval-agent: --run requires a numeric argument" >&2
        exit 1
      fi
      shift 2
      ;;
    -*)
      echo "dispatch-trigger-eval-agent: unknown flag '$1'" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "$SKILL_PATH" ]]; then
        echo "dispatch-trigger-eval-agent: only one <skill-path> allowed" >&2
        exit 1
      fi
      SKILL_PATH="$1"
      shift
      ;;
  esac
done

if [[ -z "$SKILL_PATH" ]]; then
  echo "dispatch-trigger-eval-agent: <skill-path> is required" >&2
  usage >&2
  exit 1
fi

if ! [[ "$RUNS" =~ ^[0-9]+$ ]] || (( RUNS < 1 )) || (( RUNS > 99 )); then
  echo "dispatch-trigger-eval-agent: --runs must be a number in 1..99 (got '$RUNS')" >&2
  exit 1
fi
RUNS=$((10#$RUNS))

# --- validate skill-path ---
if [[ ! -d "$SKILL_PATH" ]]; then
  echo "dispatch-trigger-eval-agent: skill-path '$SKILL_PATH' is not a directory" >&2
  exit 2
fi
if [[ ! -f "$SKILL_PATH/SKILL.md" ]]; then
  echo "dispatch-trigger-eval-agent: '$SKILL_PATH/SKILL.md' not found" >&2
  exit 2
fi

SKILL_PATH_ABS="$(cd "$SKILL_PATH" && pwd)"
SKILL_NAME="$(basename "$SKILL_PATH_ABS")"
EVAL_SET_ABS="$SKILL_PATH_ABS/evals/trigger-eval.json"

# Constrain the skill name to [A-Za-z0-9_-]+ so it stays a clean trace target=
# field and a safe path segment (mirrors dispatch-dogfood-agent.sh).
if ! [[ "$SKILL_NAME" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "dispatch-trigger-eval-agent: skill name '$SKILL_NAME' must match [A-Za-z0-9_-]+ (it becomes the trace target= field)" >&2
  exit 1
fi

# --- corpus presence (advisory: a not-yet-authored corpus -> traced skip) ---
# Mirrors the skip-no-skill-creator path exactly: trigger-eval is advisory, so a
# missing corpus is a GRACEFUL skip (exit 0), never a hard exit 2. exit 2 stays
# reserved for caller errors (skill-path-not-a-dir, missing SKILL.md) above.
if [[ ! -f "$EVAL_SET_ABS" ]]; then
  cat <<SKIP

dispatch-trigger-eval-agent: no trigger corpus yet — ADVISORY SKIP

  skill:  $SKILL_NAME
  reason: '$EVAL_SET_ABS' not found (corpus not authored yet, Phase 5).

This is ADVISORY and non-blocking: Phase 6 verify-skill remains the binding gate.
Record a TRACED skip (never a silent all-False) in .git/flow-dev-sandwich.log:

----- machine-readable handoff (eval in the main agent to fill the trace) -----
TRIGGER_EVAL_TARGET=$SKILL_NAME
TRIGGER_EVAL_VERDICT=skip-no-corpus
TRIGGER_EVAL_RUN=0
----- end handoff -----
SKIP
  exit 0
fi

# --- resolve repo root (walk up to .git/ or docs/dogfoods/) ---
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

DOGFOOD_DIR="$REPO_ROOT/docs/dogfoods/${SKILL_NAME}"

# --- resolve $SC_ROOT (advisory: a non-zero resolver -> traced skip) ---
SC_ROOT=""
if SC_ROOT="$(bash "$RESOLVER" 2>/dev/null)"; then
  : # resolved
else
  # ADVISORY skip — do NOT hard-fail the preparer. Emit a traced handoff so the
  # main agent can write verdict=skip-no-skill-creator (a traced skip, never a
  # silent all-False).
  cat <<SKIP

dispatch-trigger-eval-agent: skill-creator not resolvable — ADVISORY SKIP

  skill:  $SKILL_NAME
  reason: resolve-skill-creator.sh exited non-zero (no skill-creator install,
          or running in CI without the plugin).

This is ADVISORY and non-blocking: Phase 6 verify-skill remains the binding gate.
Record a TRACED skip (never a silent all-False) in .git/flow-dev-sandwich.log:

----- machine-readable handoff (eval in the main agent to fill the trace) -----
TRIGGER_EVAL_TARGET=$SKILL_NAME
TRIGGER_EVAL_VERDICT=skip-no-skill-creator
TRIGGER_EVAL_RUN=0
----- end handoff -----
SKIP
  exit 0
fi

# --- determine run number ---
mkdir -p "$DOGFOOD_DIR"
if [[ -z "$RUN" ]]; then
  LAST_N=0
  if compgen -G "$DOGFOOD_DIR/run-*" > /dev/null; then
    LAST_N=$(ls -1d "$DOGFOOD_DIR"/run-* 2>/dev/null \
      | sed 's|.*/run-||' \
      | grep -E '^[0-9]+$' \
      | sort -n \
      | tail -1)
    LAST_N="${LAST_N:-0}"
    LAST_N=$((10#$LAST_N))
  fi
  RUN=$((LAST_N + 1))
fi

if ! [[ "$RUN" =~ ^[0-9]+$ ]]; then
  echo "dispatch-trigger-eval-agent: --run must be numeric (got '$RUN')" >&2
  exit 1
fi
RUN=$((10#$RUN))
if (( RUN > 999 )); then
  echo "dispatch-trigger-eval-agent: run $RUN exceeds limit (999)" >&2
  exit 3
fi

RUN_ID="$(printf 'run-%03d' "$RUN")"
RUN_DIR="$DOGFOOD_DIR/$RUN_ID"

if [[ -d "$RUN_DIR" ]]; then
  echo "dispatch-trigger-eval-agent: run dir already exists at $RUN_DIR" >&2
  echo "  Pass --run <NNN> with a free number; never reuse a run id." >&2
  exit 1
fi

mkdir -p "$RUN_DIR/eval"

# --- write the BYTE-STABLE dispatch prompt ---
# CRITICAL: this file is a pure function of (SKILL_NAME, RUNS). It must NOT
# contain the run id, a date, $RANDOM, or any absolute path — anything that
# varies run-to-run would break byte-stability and make eval reports incomparable.
# The absolute paths (SC_ROOT, eval-set, skill-path) are environment-dependent, so
# the prompt references them by stable placeholder; the human-readable handoff
# block below carries the resolved absolute invocation for this run.
PROMPT_FILE="$RUN_DIR/eval/dispatch-prompt.md"
cat > "$PROMPT_FILE" <<PROMPT
# Trigger-eval (ADVISORY) — $SKILL_NAME

You are the trigger-eval agent for the skill '$SKILL_NAME'.

This step is ADVISORY and non-blocking. It runs the skill's authored trigger
corpus (evals/trigger-eval.json) against a LIVE model via skill-creator's
run_eval.py, measuring whether the description ACTUALLY causes the skill to
trigger. Phase 6 verify-skill stays the binding gate; this never blocks merge.

ANTI-SELF-GRADING INVARIANT: run_eval's output is a measurement only. NEVER wire
it into a description rewrite — the moment a measure feeds an auto-mutator,
run_loop (a rejected Non-Goal) is rebuilt. Report the numbers; do not act on them.

## What to do

1. Run the invocation printed in the preparer's handoff block (a module-style
   \`cd \$SC_ROOT && python3 -m scripts.run_eval --eval-set <abs> --skill-path <abs>
   --runs-per-query $RUNS\`). Absolute paths survive the cd; run_eval uses a
   package-relative import so it MUST run from \$SC_ROOT.
2. If \`claude\` CLI auth is dead / unavailable (CI), do NOT report an all-False
   "skill never triggers" regression. Record verdict=skip-no-auth — a TRACED skip.

## What to report

Write report.md into this run's eval/ directory with: the per-query trigger
rates run_eval reported, the overall pass/fail vs the trigger threshold, and (if
applicable) the skip reason (skip-no-auth). Report only what run_eval emitted.
Do NOT propose description rewrites.
PROMPT

# --- print dispatch instruction + machine-readable handoff ---
EVAL_INVOCATION="cd $SC_ROOT && python3 -m scripts.run_eval --eval-set $EVAL_SET_ABS --skill-path $SKILL_PATH_ABS --runs-per-query $RUNS"

cat <<INSTR

dispatch-trigger-eval-agent: trigger-eval run ready (ADVISORY)

  run dir:         $RUN_DIR
  run id:          $RUN_ID
  skill:           $SKILL_NAME
  SC_ROOT:         $SC_ROOT
  eval set:        $EVAL_SET_ABS
  runs-per-query:  $RUNS
  dispatch prompt: $PROMPT_FILE (byte-stable)

Next step — dispatch the trigger-eval agent with the prompt below. This preparer
does NOT spawn it and does NOT execute run_eval (bash cannot drive \`claude -p\`);
the main agent dispatches. The exact invocation the agent should run:

  $EVAL_INVOCATION

----- machine-readable handoff (eval in the main agent to fill the trace) -----
TRIGGER_EVAL_TARGET=$SKILL_NAME
TRIGGER_EVAL_RUN=$RUN
TRIGGER_EVAL_SC_ROOT=$SC_ROOT
TRIGGER_EVAL_INVOCATION=$EVAL_INVOCATION
----- end handoff -----

The trigger-eval completion trace the main agent writes (skill-writer/SKILL.md
Phase 5) MUST carry \`target=\$TRIGGER_EVAL_TARGET\` so the SOFT boundary assert
cross-checks docs/dogfoods/\$TRIGGER_EVAL_TARGET/run-NNN/eval (the dir created
above), NOT skill-writer/.

----- trigger-eval prompt (byte-stable; from $PROMPT_FILE) -----

$(cat "$PROMPT_FILE")

----- End prompt -----

Trigger-eval is an ADVISORY live-model complement to verify-skill, NOT a
replacement. verify-skill (skill-writer Phase 6) remains the mandatory gate, and
run_eval's output is NEVER fed into a description mutator.
INSTR

exit 0
